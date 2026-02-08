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

module Wacli
  class CLI
    def self.run(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : Int32
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
      else
        return run_request(argv, stdout, stderr)
      end
    end

    private def self.run_oas(argv : Array(String), stdout : IO, stderr : IO) : Int32
      return usage(stdout) if argv.empty?

      case argv[0]?
      when "validate"
        return oas_validate(argv[1..], stdout, stderr)
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

      cfg = Config.load
      resolved = ToolResolver.resolve(tool_ref, cfg)
      doc = OpenAPI::Loader.load_any(resolved.api_url)
      base = OpenAPI::BaseUrl.compute(doc, tool_ref)

      stdout.puts "tool: #{tool_ref}"
      stdout.puts "source: #{resolved.source}"
      stdout.puts "openapi: #{doc.version_string}"
      stdout.puts "base_url: #{base}"
      stdout.puts "operations:"
      OpenAPI::Router.list_operations(doc).each do |op|
        stdout.puts "  - #{op}"
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

    private def self.run_request(argv : Array(String), stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]
      rest = argv[1..]
      if rest.empty?
        stderr.puts "missing operation tokens"
        return 1
      end

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

      cfg = Config.load
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
        json_body: json_body,
        bearer_token: token,
        bearer_header: resolved.manifest.bearer_header_name
      )

      if dry_run
        stdout.puts req.to_dry_run
        return 0
      end

      resp = req.execute
      stdout.puts resp.body
      (resp.status_code >= 200 && resp.status_code < 300) ? 0 : 1
    rescue ex
      stderr.puts ex.message
      1
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
        wacli help <tool_ref>
        wacli ain <tool_ref>
        wacli auth <tool_ref> --bearer TOKEN
        wacli <tool_ref> [method] <path_tokens...> [key=value...] [--json STR] [--header k:v] [--dry-run]
      TXT
      1
    end
  end
end
