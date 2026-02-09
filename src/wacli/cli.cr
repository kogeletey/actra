require "option_parser"
require "json"
require "file_utils"

require "./xdg"
require "./config"
require "./manifest"
require "./secrets"
require "./request"
require "./tool_resolver"
require "./tool_key"
require "./openapi/loader"
require "./openapi/compat"
require "./openapi/base_url"
require "./openapi/router"
require "./openapi/hints"
require "./openapi/dto"
require "./openapi/schema_printer"
require "./plugins/oas_validate"
require "./render/engine"
require "./render/mode"
require "./interactive/prompt"
require "./interactive/json_builder"
require "./interactive/form_builder"

module Wacli
  class CLI
    def self.run(argv : Array(String), stdin : IO = STDIN, stdout : IO = STDOUT, stderr : IO = STDERR) : Int32
      return usage(stdout) if argv.empty?

      case argv[0]
      when "shell"
        return run_shell(argv[1..], stdout, stderr)
      when "oas"
        return run_oas(argv[1..], stdout, stderr)
      when "help"
        return run_help(argv[1..], stdout, stderr)
      when "ain"
        return run_ain(argv[1..], stdout, stderr)
      when "auth"
        return run_auth(argv[1..], stdout, stderr)
      when "render"
        return run_render(argv[1..], stdin, stdout, stderr)
      else
        return run_request(argv, stdin, stdout, stderr)
      end
    end

    private def self.run_oas(argv : Array(String), stdout : IO, stderr : IO) : Int32
      return usage(stdout) if argv.empty?

      case argv[0]?
      when "validate"
        return Plugins::OasValidate.run(argv[1..], stdout, stderr)
      else
        stderr.puts "unknown subcommand: oas #{argv[0]}"
        return 1
      end
    end

    private def self.run_help(argv : Array(String), stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]?
      unless tool_ref
        stderr.puts "missing <tool_ref>"
        return 1
      end

      # Optional detailed help:
      #   wacli help <tool_ref> [method] <path_tokens...>
      op_method = nil.as(String?)
      op_tokens = [] of String
      if argv.size > 1
        rest = argv[1..]
        if rest[0]? && http_method_token?(rest[0])
          op_method = rest[0].downcase
          rest = rest[1..]
        end
        op_tokens = rest
      end

      cfg = Config.load
      resolved = ToolResolver.resolve(tool_ref, cfg)
      doc = OpenAPI::Loader.load_any(resolved.api_url)
      base = OpenAPI::BaseUrl.compute(doc, tool_ref)

      stdout.puts "tool: #{tool_ref}"
      stdout.puts "source: #{resolved.source}"
      stdout.puts "openapi: #{doc.version_string}"
      stdout.puts "base_url: #{base}"

      if op_tokens.any?
        method = op_method || "get"
        op = OpenAPI::Router.match(doc, method, resolved.manifest.expand_path_tokens(op_tokens))
        builder = OpenAPI::Dto::Builder.new(doc)
        dto = builder.operation(op.method, op.path_template)

        stdout.puts
        stdout.puts "operation: #{dto.method.upcase} #{dto.path_template}"
        if dto.summary
          stdout.puts "summary: #{dto.summary}"
        end
        if dto.description
          stdout.puts "description:"
          dto.description.not_nil!.lines.each { |l| stdout.puts "  #{l.rstrip}" }
        end

        if dto.parameters.any?
          stdout.puts "parameters:"
          dto.parameters.each do |p|
            ty = p.schema.try(&.type) || "unknown"
            req = p.required ? "required" : "optional"
            desc = p.description ? " - #{p.description}" : ""
            stdout.puts "  - #{p.location} #{p.name}: #{ty} (#{req})#{desc}"
          end
        end

        if rb = dto.request_body_json
          stdout.puts "requestBody:"
          stdout.puts "  content-type: #{rb.content_type}"
          stdout.puts "  schema:"
          OpenAPI::SchemaPrinter.print(rb.schema, stdout, 4)
          stdout.puts "  interactive:"
          fields = Interactive::FormBuilder.fields_for_schema(rb.schema)
          if fields.empty?
            stdout.puts "    (none)"
          else
            fields.each do |f|
              k = f.kind.to_s.downcase
              extra =
                if f.kind == Render::FieldKind::Enum
                  " values=#{f.enum_values.join(",")}"
                else
                  ""
                end
              stdout.puts "    - #{f.pointer} kind=#{k} required=#{f.required} prompt=#{f.prompt}#{extra}"
            end
          end
        end
      else
        stdout.puts "operations:"
        builder = OpenAPI::Dto::Builder.new(doc)
        builder.list_operations.each do |i|
          if i.summary
            stdout.puts "  - #{i.method.upcase} #{i.path_template} - #{i.summary}"
          else
            stdout.puts "  - #{i.method.upcase} #{i.path_template}"
          end
        end
      end

      if resolved.manifest.path_aliases.any?
        stdout.puts "path_aliases:"
        resolved.manifest.path_aliases.each do |k, v|
          stdout.puts "  - #{k} => #{v}"
        end
      end

      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_ain(argv : Array(String), stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]?
      unless tool_ref
        stderr.puts "missing <tool_ref>"
        return 1
      end

      cfg = Config.load
      resolved = ToolResolver.resolve(tool_ref, cfg)
      doc = OpenAPI::Loader.load_any(resolved.api_url)
      report = OpenAPI::Compat.validate(doc)
      unless report.ok
        stdout.puts report.to_text
        return 3
      end

      key = ToolKey.for(tool_ref)
      cache_path = Cache.ain_path(key)
      FileUtils.mkdir_p(File.dirname(cache_path))
      # Ensure we fetch from the original URL (not a cached file path).
      source_url = resolved.api_url
      if !source_url.starts_with?("http://") && !source_url.starts_with?("https://")
        if e = Lock.load.get_ain(key)
          if s = e["source"]?
            source_url = s
          end
        end
      end

      json_text = OpenAPI::Loader.fetch_text(source_url)
      File.write(cache_path, json_text)

      lock = Lock.load
      lock.set_ain(key, source_url, cache_path, doc.version_string, Lock.sha256(json_text))
      lock.save

      stdout.puts "cached: #{cache_path}"
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_auth(argv : Array(String), stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]?
      unless tool_ref
        stderr.puts "missing <tool_ref>"
        return 1
      end

      token = nil.as(String?)
      parser = OptionParser.new do |p|
        p.on("--bearer TOKEN", "Set bearer token") { |t| token = t }
      end
      parser.parse(argv[1..])

      unless token
        stderr.puts "missing --bearer TOKEN"
        return 1
      end

      cfg = Config.load
      key = ToolKey.for(tool_ref)
      Secrets.new(cfg.db_path).set_bearer(key, token.not_nil!)
      stdout.puts "stored bearer token for #{key}"
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_render(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      in_file = nil.as(String?)
      mode_s = nil.as(String?)

      parser = OptionParser.new do |p|
        p.on("--in FILE", "Input file (default: stdin)") { |v| in_file = v }
        p.on("--render MODE", "Render mode: auto|table|json|raw") { |v| mode_s = v }
      end
      parser.parse(argv)

      cfg = Config.load
      mode = Render::Mode.parse(mode_s) || cfg.render.default_mode

      bytes =
        if in_file
          File.read(in_file.not_nil!).to_slice
        else
          io = IO::Memory.new
          IO.copy(stdin, io)
          io.to_slice
        end

      Render::Engine.render(bytes, mode, stdout, cfg.render)
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_request(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]
      rest = argv[1..]
      if rest.empty?
        stderr.puts "missing operation tokens"
        return 1
      end

      cfg = Config.load

      method = "get"
      if http_method_token?(rest[0])
        method = rest[0].downcase
        rest = rest[1..]
      end

      path_tokens = [] of String
      idx = 0
      while idx < rest.size
        a = rest[idx]
        break if a.starts_with?("--") || a.includes?('=')
        path_tokens << a
        idx += 1
      end
      opts = rest[idx..]

      json_body = nil.as(String?)
      out_path = nil.as(String?)
      render_mode_s = nil.as(String?)
      interactive_force = false
      interactive_disable = false
      dry_run = false
      extra_headers = [] of Tuple(String, String)
      query_kv = [] of Tuple(String, String)

      # Remaining args: key=value or flags
      i = 0
      while i < opts.size
        a = opts[i]
        if a == "--dry-run"
          dry_run = true
          i += 1
        elsif a == "--json"
          json_body = opts[i + 1]? || raise "missing value for --json"
          i += 2
        elsif a == "--out"
          out_path = opts[i + 1]? || raise "missing value for --out"
          i += 2
        elsif a == "--render"
          render_mode_s = opts[i + 1]? || raise "missing value for --render"
          i += 2
        elsif a == "--interactive"
          interactive_force = true
          i += 1
        elsif a == "--no-interactive"
          interactive_disable = true
          i += 1
        elsif a == "--header"
          hv = opts[i + 1]? || raise "missing value for --header"
          parts = hv.split(":", 2)
          raise "invalid header format, expected k:v" unless parts.size == 2
          extra_headers << {parts[0].strip, parts[1].strip}
          i += 2
        elsif a.includes?('=')
          parts = a.split("=", 2)
          query_kv << {parts[0], parts[1]}
          i += 1
        else
          raise "unknown argument: #{a}"
        end
      end

      resolved = ToolResolver.resolve(tool_ref, cfg)
      doc = OpenAPI::Loader.load_any(resolved.api_url)
      report = OpenAPI::Compat.validate(doc)
      raise report.to_text unless report.ok

      base_url = OpenAPI::BaseUrl.compute(doc, tool_ref)
      op = OpenAPI::Router.match(doc, method, resolved.manifest.expand_path_tokens(path_tokens))

      # Auth works in both modes: manifest-based and fallback (/openapi.json,/swagger.json).
      token = Secrets.new(cfg.db_path).get_bearer(ToolKey.for(tool_ref))

      req = Request.build(
        base_url: base_url,
        method: op.method,
        path_template: op.path_template,
        path_param_names: op.path_param_names,
        path_param_values: op.path_param_values,
        query: query_kv,
        headers: resolved.manifest.headers + extra_headers,
        json_body: resolve_json_body(
          json_body: json_body,
          stdin: stdin,
          stdout: stdout,
          op_method: op.method,
          op_path_template: op.path_template,
          doc: doc,
          cfg: cfg,
          interactive_force: interactive_force,
          interactive_disable: interactive_disable
        ),
        bearer_token: token,
        bearer_header: resolved.manifest.bearer_header_name
      )

      if dry_run
        stdout.puts req.to_dry_run
        return 0
      end

      resp = req.execute
      return handle_response(resp, out_path, render_mode_s, stdin, stdout, stderr, cfg)
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.handle_response(resp : Response, out_path : String?, render_mode_s : String?, stdin : IO, stdout : IO, stderr : IO, cfg : Config) : Int32
      ok = resp.status_code >= 200 && resp.status_code < 300

      if out_path
        if out_path == "-"
          stdout.write(resp.body_bytes)
          return ok ? 0 : 1
        end

        File.open(out_path, "wb") { |f| f.write(resp.body_bytes) }
        stderr.puts "http: #{resp.status_code}"
        stderr.puts "saved: #{out_path}"
        return ok ? 0 : 1
      end

      mode = Render::Mode.parse(render_mode_s) || cfg.render.default_mode
      # If the user explicitly asked for raw rendering, don't second-guess them.
      if mode != Render::Mode::Raw && should_save_as_file?(resp, mode)
        if stdin.tty?
          default_name = resp.attachment_filename || "download.bin"
          path = prompt_out_path(stdin, stdout, "Save as", default_name)
          File.open(path, "wb") { |f| f.write(resp.body_bytes) }
          stderr.puts "http: #{resp.status_code}"
          stderr.puts "saved: #{path}"
          return ok ? 0 : 1
        else
          raise "response looks like a file; re-run with --out PATH"
        end
      end

      Render::Engine.render(resp.body_bytes, mode, stdout, cfg.render)
      ok ? 0 : 1
    end

    private def self.prompt_out_path(stdin : IO, stdout : IO, label : String, default_name : String) : String
      loop do
        stdout.print "#{label} [#{default_name}]: "
        stdout.flush
        s = stdin.gets
        raise "EOF while reading output path" unless s
        v = s.strip
        v = default_name if v.empty?
        return v unless v.empty?
      end
    end

    private def self.should_save_as_file?(resp : Response, mode : Render::Mode) : Bool
      return true if resp.attachment?
      ct = resp.content_type
      if ct
        ct_l = ct.downcase
        return false if ct_l.includes?("json") || ct_l.ends_with?("+json")
        return false if ct_l.starts_with?("text/")
        return true if ct_l.starts_with?("application/octet-stream")
        # For other application/* types: treat as downloadable if it's not obviously text-like.
        return ct_l.starts_with?("application/")
      end

      # No content-type: if it parses as JSON, render it; else if it has NUL bytes, treat as binary.
      begin
        JSON.parse(String.new(resp.body_bytes))
        return false
      rescue
      end
      resp.body_bytes.any? { |b| b == 0_u8 }
    end

    private def self.resolve_json_body(
      json_body : String?,
      stdin : IO,
      stdout : IO,
      op_method : String,
      op_path_template : String,
      doc : OpenAPI::Document,
      cfg : Config,
      interactive_force : Bool,
      interactive_disable : Bool
    ) : String?
      # 1) Explicit --json
      if json_body
        return read_json_arg(json_body, stdin, stdout, cfg)
      end

      # 2) Non-TTY: allow piping JSON for write methods.
      if !stdin.tty? && {"post", "put", "patch"}.includes?(op_method.downcase)
        io = IO::Memory.new
        IO.copy(stdin, io)
        txt = String.new(io.to_slice).strip
        return txt unless txt.empty?
      end

      # 3) Interactive prompt on TTY for write methods (or if forced).
      wants_prompt = interactive_force || {"post", "put", "patch"}.includes?(op_method.downcase)
      return nil unless wants_prompt
      return nil if interactive_disable
      return nil unless stdin.tty?
      return nil unless cfg.render.interactive.enabled

      op_key = "#{op_method.upcase} #{op_path_template}"
      rule = cfg.render.operations[op_key]?
      fields =
        if rule
          rule.fields
        else
          begin
            builder = OpenAPI::Dto::Builder.new(doc)
            dto = builder.operation(op_method, op_path_template)
            rb = dto.request_body_json
            if rb
              Interactive::FormBuilder.fields_for_schema(rb.schema)
            else
              OpenAPI::Hints.fields_for(doc, op_method, op_path_template)
            end
          rescue
            OpenAPI::Hints.fields_for(doc, op_method, op_path_template)
          end
        end

      raise "no interactive schema for #{op_key}; provide --json or configure wacfg.json render.operations" if fields.empty?

      b = Interactive::JsonBuilder.new
      fields.each do |f|
        value_any : JSON::Any =
          case f.kind
          when Render::FieldKind::String
            JSON::Any.new(Interactive::Prompt.ask_string(stdin, stdout, f.prompt, f.required))
          when Render::FieldKind::Boolean
            JSON::Any.new(Interactive::Prompt.ask_bool(stdin, stdout, f.prompt, f.default_bool))
          when Render::FieldKind::Enum
            JSON::Any.new(Interactive::Prompt.ask_enum(stdin, stdout, f.prompt, f.enum_values, cfg.render))
          when Render::FieldKind::DateTime
            JSON::Any.new(Interactive::Prompt.ask_datetime(stdin, stdout, f.prompt, cfg.render))
          when Render::FieldKind::File
            JSON::Any.new(Interactive::Prompt.ask_file_path(stdin, stdout, f.prompt, cfg.render))
          when Render::FieldKind::Json
            Interactive::Prompt.ask_json(stdin, stdout, f.prompt, f.required)
          else
            raise "unsupported interactive field kind: #{f.kind}"
          end
        b.set_pointer(f.pointer, value_any)
      end

      b.to_json
    end

    private def self.read_json_arg(arg : String, stdin : IO, stdout : IO, cfg : Config) : String
      if arg.starts_with?("@")
        rest = arg[1..]
        if rest.empty?
          # "@": pick a file on TTY if possible.
          raise "stdin is not a TTY; use --json @path/to/file.json" unless stdin.tty?
          path = Interactive::Prompt.ask_file_path(stdin, stdout, "JSON file", cfg.render)
          return File.read(path)
        end
        return File.read(rest)
      end
      arg
    end

    private def self.run_shell(argv : Array(String), stdout : IO, stderr : IO) : Int32
      shell = argv[0]?
      unless shell
        stderr.puts "missing <bash|zsh>"
        return 1
      end
      unless shell == "bash" || shell == "zsh"
        stderr.puts "unsupported shell: #{shell} (expected bash or zsh)"
        return 1
      end

      installed = false
      tool_refs = [] of String
      argv[1..].each do |a|
        if a == "--installed"
          installed = true
        else
          tool_refs << a
        end
      end

      if installed
        Lock.load.ains.keys.each { |k| tool_refs << k }
      end
      tool_refs = tool_refs.uniq
      if tool_refs.empty?
        stderr.puts "no tools provided (use: wacli shell #{shell} <tool_ref...> or --installed)"
        return 1
      end

      tool_refs.each do |ref|
        name = ToolKey.for(ref)
        if name.empty? || name.matches?(/\s/) || name.includes?('=') || name.includes?('/')
          raise "invalid alias name: #{name}"
        end
        stdout.puts "alias #{name}=#{shell_sq("wacli #{ref}")}"
      end
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.oas_validate(argv : Array(String), stdout : IO, stderr : IO) : Int32
      path_or_url = argv[0]?
      unless path_or_url
        stderr.puts "missing <file_or_url>"
        return 1
      end

      begin
        doc = OpenAPI::Loader.load_any(path_or_url)
        report = OpenAPI::Compat.validate(doc)
        stdout.puts report.to_text
        return report.exit_code
      rescue ex : OpenAPI::UnsupportedVersionError
        stdout.puts "ok: false\nerrors:\n  - #{ex.message}"
        return 2
      rescue ex
        stderr.puts ex.message
        return 3
      end
    end

    private def self.shell_sq(s : String) : String
      # POSIX-like single-quote escaping: ' becomes '\'' in the resulting shell string.
      "'" + s.gsub("'", %q('"'"')) + "'"
    end

    private def self.http_method_token?(s : String) : Bool
      case s.downcase
      when "get", "post", "put", "patch", "delete", "head", "options"
        true
      else
        false
      end
    end

    private def self.usage(io : IO) : Int32
      io.puts <<-TXT
      wacli (v0.1)

      Commands:
        wacli shell <bash|zsh> [--installed] <tool_ref...>
        wacli oas validate <file_or_url>
        wacli help <tool_ref> [method] <path_tokens...>
        wacli ain <tool_ref>
        wacli auth <tool_ref> --bearer TOKEN
        wacli render [--render MODE] [--in FILE]
        wacli <tool_ref> [method] <path_tokens...> [key=value...] [--json STR] [--header k:v] [--render MODE] [--out PATH] [--interactive|--no-interactive] [--dry-run]

      Render MODE:
        auto|table|json|raw

      JSON bodies:
        --json STR             Inline JSON string
        --json @file.json      Read JSON from file
        --json @               Pick a JSON file (uses fzf if available, otherwise prompts for a path)
      TXT
      1
    end
  end
end
