require "option_parser"
require "json"
require "file_utils"
require "random/secure"

require "./xdg"
require "./config"
require "./manifest"
require "./secrets"
require "./request"
require "./tool_resolver"
require "./tool_key"
require "./activation"
require "./dispatch"
require "./agent"
require "./packages"
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

module Actra
  class CLI
    def self.run(argv : Array(String), stdin : IO = STDIN, stdout : IO = STDOUT, stderr : IO = STDERR) : Int32
      return usage(stdout) if argv.empty?
      return usage(stdout) if {"-h", "--help"}.includes?(argv[0])
      return version(stdout) if {"-v", "--version"}.includes?(argv[0])
      return run_crystal_extension(argv[1..], stdin, stdout, stderr) if argv[0] == "__cr-extension"
      return run_at_menu(argv[1..], stdin, stdout, stderr) if argv[0] == "@"
      if argv[0] == "@?"
        stderr.puts "unknown command: @?"
        return 1
      end
      return Dispatch.run(["--command", argv[0], "--"] + argv[1..], stdin, stdout, stderr) if argv[0].starts_with?("@")
      return run_query(argv[1..], stdin, stdout, stderr) if argv[0] == "?"
      if argv[0].starts_with?("?") && argv[0].size > 1
        query_ref = argv[0][1..]
        explicit_query = {"help", "info", "docs", "doc", "launch", "run"}.includes?(argv[1]?)
        return run_query([query_ref] + argv[1..], stdin, stdout, stderr) if explicit_query || looks_like_tool_ref?(query_ref)
      end
      return run_agent(parse_agent_options(argv), stdin, stdout, stderr) if agent_invocation?(argv)

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
      when "activate"
        return run_activate(argv[1..], stdout, stderr)
      when "config"
        return run_config(argv[1..], stdout, stderr)
      when "dispatch"
        return Dispatch.run(argv[1..], stdin, stdout, stderr)
      when "query"
        return run_query(argv[1..], stdin, stdout, stderr)
      when "launch"
        return run_launch(argv[1..], stdin, stdout, stderr)
      when "complete", "completion"
        return run_complete(argv[1..], stdout, stderr)
      when "agent"
        return run_agent(parse_agent_options(argv[1..]), stdin, stdout, stderr)
      when "package", "pkg", "install", "remove", "uninstall", "update", "list"
        package_argv = {"package", "pkg"}.includes?(argv[0]) ? argv[1..] : argv
        return Packages.run(package_argv, stdout, stderr)
      when "__cr-extension"
        return run_crystal_extension(argv[1..], stdin, stdout, stderr)
      else
        return run_request(argv, stdin, stdout, stderr)
      end
    end

    private def self.agent_invocation?(argv : Array(String)) : Bool
      first = argv[0]
      return true if {"-p", "--print", "--mode", "--provider", "--model", "--api-key", "--thinking", "--models", "--list-models", "--list-prompts", "--permission-state", "--permission-allow", "--permission-deny", "--permission-revoke", "--permission-clear", "--system-prompt", "--append-system-prompt", "--prompt", "--prompt-mode", "--no-context-files", "-nc", "--no-session", "--session", "--session-dir", "-c", "--continue", "-r", "--resume", "--fork", "--export", "-e", "--extension", "--no-extensions", "--skill", "--no-skills", "--prompt-template", "--no-prompt-templates", "--tools", "-t", "--no-tools", "-nt", "--no-builtin-tools", "-nbt", "--permission-mode", "--restrictive", "-R", "--accept-all", "--yolo", "--sandbox", "--no-sandbox"}.includes?(first)
      return true if !known_command?(first) && !looks_like_tool_ref?(first)
      false
    end

    private def self.known_command?(first : String) : Bool
      {"shell", "oas", "help", "ain", "auth", "activate", "config", "dispatch", "query", "launch", "complete", "completion", "agent", "@", "package", "pkg", "install", "remove", "uninstall", "update", "list", "render", "__cr-extension"}.includes?(first)
    end

    private def self.looks_like_tool_ref?(first : String) : Bool
      first.starts_with?("http://") || first.starts_with?("https://") || first.starts_with?("registry:") || first.includes?("/") || first.includes?(".")
    end

    private def self.normalize_tool_ref_arg(arg : String) : String
      return arg unless arg.starts_with?("@")
      rest = arg[1..]
      return arg if rest.includes?("@")
      rest
    end

    private def self.run_at_file_action_menu(path : String, stdin : IO, stdout : IO, stderr : IO) : Int32
      open_action = editor_action_label(path)
      absolute = File.expand_path(path)
      directory = File.directory?(absolute)
      actions = ["insert @path in console", "open in editor", "copy absolute path", "insert absolute path in console", "go to folder"]
      unless directory
        actions.insert(4, "run executable")
        actions << "delete file"
      end
      if open_action != "open in editor"
        actions.insert(1, open_action)
      end
      action = Interactive::PickerTui.pick_one("File action", actions)
      case action
      when "insert @path in console"
        shell_insert(Interactive::PickerTui.context_tokens([path]), stdout)
      when open_action, "open in editor"
        open_in_default_editor(path, stdin, stdout, stderr)
      when "copy absolute path"
        copy_absolute_path(path, stdout, stderr)
      when "insert absolute path in console"
        shell_insert(shell_sq(File.expand_path(path)), stdout)
      when "run executable"
        run_executable_file(path, stdin, stdout, stderr)
      when "go to folder"
        shell_cd(directory ? absolute : File.dirname(absolute), stdout)
      when "delete file"
        delete_file(path, stdout, stderr)
      else
        stderr.puts "no action selected"
        1
      end
    end

    private def self.shell_insert(value : String, stdout : IO) : Int32
      if ENV["ACTRA_SHELL_HOOK"]? == "1"
        stdout.puts "__ACTRA_INSERT__#{value}"
      else
        stdout.puts value
      end
      0
    end

    private def self.shell_cd(path : String, stdout : IO) : Int32
      if ENV["ACTRA_SHELL_HOOK"]? == "1"
        stdout.puts "__ACTRA_CD__#{path}"
      else
        stdout.puts "cd #{shell_sq(path)}"
      end
      0
    end

    private def self.executable_file?(path : String) : Bool
      absolute = File.expand_path(path)
      return false unless File.file?(absolute)

      Process.run("test", ["-x", absolute], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
    rescue
      false
    end

    private def self.run_executable_file(path : String, stdin : IO, stdout : IO, stderr : IO) : Int32
      absolute = File.expand_path(path)
      unless executable_file?(absolute)
        stderr.puts "not executable: #{absolute}"
        return 1
      end

      status = Process.run(absolute, [] of String, input: stdin, output: stdout, error: stderr)
      status.exit_code
    end

    private def self.delete_file(path : String, stdout : IO, stderr : IO) : Int32
      absolute = File.expand_path(path)
      unless File.file?(absolute)
        stderr.puts "not a file: #{absolute}"
        return 1
      end

      File.delete(absolute)
      stdout.puts "deleted: #{absolute}"
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.editor_action_label(path : String) : String
      absolute = File.expand_path(path)
      cfg = Config.load
      editor = cfg.editor_for_file(absolute) || ENV["VISUAL"]? || ENV["EDITOR"]? || platform_opener
      editor && !editor.empty? ? "open with #{editor_label(editor)}" : "open in editor"
    end

    private def self.open_in_default_editor(path : String, stdin : IO, stdout : IO, stderr : IO) : Int32
      absolute = File.expand_path(path)
      cfg = Config.load
      editor = cfg.editor_for_file(absolute) || ENV["VISUAL"]? || ENV["EDITOR"]?
      if editor && !editor.empty?
        status = Process.run("/bin/sh", ["-c", editor_command(editor, absolute)], input: stdin, output: stdout, error: stderr)
        return status.exit_code
      end

      opener = platform_opener
      unless opener
        stderr.puts "no default editor found; set VISUAL or EDITOR"
        return 1
      end

      status = Process.run(opener, [absolute], input: stdin, output: stdout, error: stderr)
      status.exit_code
    end

    private def self.platform_opener : String?
      if Process.find_executable("xdg-open")
        "xdg-open"
      elsif Process.find_executable("open")
        "open"
      end
    end

    private def self.editor_label(editor : String) : String
      command = editor.strip.split(/\s+/, 2)[0]? || editor
      File.basename(command.gsub(/^["']|["']$/, ""))
    end

    private def self.editor_command(editor : String, absolute_path : String) : String
      quoted_path = shell_sq(absolute_path)
      if editor.includes?("{}")
        editor.gsub("{}", quoted_path)
      else
        "#{editor} #{quoted_path}"
      end
    end

    private def self.copy_absolute_path(path : String, stdout : IO, stderr : IO) : Int32
      absolute = File.expand_path(path)
      copied =
        if Process.find_executable("wl-copy")
          copy_to_command("wl-copy", [] of String, absolute)
        elsif Process.find_executable("pbcopy")
          copy_to_command("pbcopy", [] of String, absolute)
        elsif Process.find_executable("xclip")
          copy_to_command("xclip", ["-selection", "clipboard"], absolute)
        elsif Process.find_executable("xsel")
          copy_to_command("xsel", ["--clipboard", "--input"], absolute)
        else
          false
        end

      stdout.puts absolute
      if copied
        stderr.puts "copied absolute path"
        0
      else
        stderr.puts "no clipboard command found; printed absolute path"
        1
      end
    end

    private def self.copy_to_command(command : String, args : Array(String), value : String) : Bool
      input = IO::Memory.new(value)
      status = Process.run(command, args, input: input, output: Process::Redirect::Close, error: Process::Redirect::Close)
      status.success?
    rescue
      false
    end

    private def self.run_complete(argv : Array(String), stdout : IO, stderr : IO) : Int32
      kind = argv[0]? || "at"
      prefix = argv[1]? || ""
      candidates =
        case kind
        when "at", "@"
          at_completion_candidates(prefix)
        when "actors", "actor"
          actor_completion_candidates
        when "files", "file"
          Interactive::PickerTui.file_context_candidates(prefix)
        else
          stderr.puts "unknown completion kind: #{kind}"
          return 1
        end

      candidates.each { |candidate| stdout.puts candidate }
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.at_completion_candidates(prefix : String) : Array(String)
      candidates = actor_completion_candidates + action_completion_candidates + at_built_in_action_candidates + Interactive::PickerTui.file_context_candidates(prefix)
      candidates.select { |candidate| completion_match?(candidate, prefix) }.uniq.sort
    end

    private def self.at_built_in_action_candidates : Array(String)
      ["agent", "run", "background", "remote", "container"]
    end

    private def self.action_completion_candidates : Array(String)
      Config.load.at.menu_actions.map(&.label)
    end

    private def self.completion_match?(candidate : String, prefix : String) : Bool
      return true if prefix.empty?
      candidate.starts_with?(prefix) || candidate.lchop("@").starts_with?(prefix)
    end

    private def self.actor_completion_candidates : Array(String)
      cfg = Config.load
      commands = ["@"] of String
      cfg.servers.each_value do |server|
        server.actors.each { |actor| commands << actor.command }
      end
      commands.uniq.sort
    end

    private def self.crystal_command : String
      ENV["CRYSTAL"]? || "crystal"
    end

    private def self.parse_agent_options(argv : Array(String)) : AgentOptions
      opts = AgentOptions.new
      i = 0
      while i < argv.size
        arg = argv[i]
        case arg
        when "-p", "--print"
          opts.print_mode = true
          i += 1
        when "--mode"
          opts.io_mode = argv[i + 1]? || raise "missing value for --mode"
          i += 2
        when "--provider"
          opts.provider = argv[i + 1]? || raise "missing value for --provider"
          i += 2
        when "--model"
          opts.model = argv[i + 1]? || raise "missing value for --model"
          i += 2
        when "--api-key"
          opts.api_key = argv[i + 1]? || raise "missing value for --api-key"
          i += 2
        when "--thinking", "--models", "--tools", "-t"
          if {"--tools", "-t"}.includes?(arg)
            opts.allowed_tools = (argv[i + 1]? || raise "missing value for #{arg}").split(",").map(&.strip).reject(&.empty?)
          end
          i += 2
        when "--no-tools", "-nt"
          opts.tools_enabled = false
          i += 1
        when "--no-builtin-tools", "-nbt"
          opts.builtin_tools_enabled = false
          i += 1
        when "--permission-mode"
          opts.permission_mode = PermissionMode.from(argv[i + 1]? || raise "missing value for --permission-mode")
          i += 2
        when "--restrictive", "-R"
          opts.permission_mode = PermissionMode::Restrictive
          i += 1
        when "--accept-all"
          opts.permission_mode = PermissionMode::AcceptAll
          i += 1
        when "--yolo"
          opts.permission_mode = PermissionMode::Yolo
          i += 1
        when "--sandbox"
          opts.sandbox = true
          i += 1
        when "--no-sandbox"
          opts.sandbox = false
          i += 1
        when "--no-skills", "--no-prompt-templates"
          i += 1
        when "--list-models"
          if (value = argv[i + 1]?) && !value.starts_with?("-")
            opts.list_models = value
            i += 2
          else
            opts.list_models = ""
            i += 1
          end
        when "--system-prompt"
          opts.system_prompt = argv[i + 1]? || raise "missing value for --system-prompt"
          i += 2
        when "--append-system-prompt"
          opts.append_system_prompt = argv[i + 1]? || raise "missing value for --append-system-prompt"
          i += 2
        when "--prompt", "--prompt-mode"
          opts.prompt_modes << (argv[i + 1]? || raise "missing value for #{arg}")
          i += 2
        when "--list-prompts"
          opts.list_prompts = true
          i += 1
        when "--permission-state"
          opts.permission_state = true
          i += 1
        when "--permission-allow"
          opts.permission_allows << parse_permission_entry((argv[i + 1]? || raise "missing value for --permission-allow"), "--permission-allow")
          i += 2
        when "--permission-deny"
          opts.permission_denies << parse_permission_entry((argv[i + 1]? || raise "missing value for --permission-deny"), "--permission-deny")
          i += 2
        when "--permission-revoke"
          opts.permission_revokes << parse_permission_entry((argv[i + 1]? || raise "missing value for --permission-revoke"), "--permission-revoke")
          i += 2
        when "--permission-clear"
          opts.permission_clear = true
          i += 1
        when "--no-context-files", "-nc"
          opts.context_files = false
          i += 1
        when "--no-session"
          opts.save_session = false
          i += 1
        when "-c", "--continue", "-r", "--resume"
          opts.continue_session = true
          i += 1
        when "--session"
          opts.session = argv[i + 1]? || raise "missing value for --session"
          i += 2
        when "--fork"
          opts.fork_session = argv[i + 1]? || raise "missing value for --fork"
          i += 2
        when "--session-dir"
          opts.session_dir = argv[i + 1]? || raise "missing value for --session-dir"
          i += 2
        when "--export"
          opts.export_in = argv[i + 1]? || raise "missing value for --export"
          if (value = argv[i + 2]?) && !value.starts_with?("-")
            opts.export_out = value
            i += 3
          else
            i += 2
          end
        when "-e", "--extension"
          opts.explicit_extensions << (argv[i + 1]? || raise "missing value for --extension")
          i += 2
        when "--no-extensions"
          opts.extensions_enabled = false
          i += 1
        when "--skill"
          opts.skills << (argv[i + 1]? || raise "missing value for --skill")
          i += 2
        when "--prompt-template"
          opts.prompt_templates << (argv[i + 1]? || raise "missing value for --prompt-template")
          i += 2
        else
          opts.prompt_args << arg
          i += 1
        end
      end
      opts
    end

    private def self.parse_permission_entry(value : String, flag : String) : PermissionAllowEntry
      separator = value.index(":") || raise "missing TOOL:PATTERN value for #{flag}"
      tool = value[0...separator].strip
      pattern = value[(separator + 1)..].strip
      raise "missing tool in #{flag}" if tool.empty?
      raise "missing pattern in #{flag}" if pattern.empty?
      PermissionAllowEntry.new(tool, pattern)
    end

    private def self.run_agent(opts : AgentOptions, stdin : IO, stdout : IO, stderr : IO) : Int32
      Agent.run(opts, stdin, stdout, stderr)
    end

    private def self.run_crystal_extension(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      source = argv[0]? || raise "missing crystal extension source"
      sdk_path = File.join(__DIR__, "extension_api.cr")
      raise "missing Crystal extension SDK: #{sdk_path}" unless File.file?(sdk_path)
      raise "missing Crystal extension: #{source}" unless File.file?(source)

      tmp_dir = File.join(Dir.tempdir, "actra-cr-extension")
      FileUtils.mkdir_p(tmp_dir)
      tmp_path = File.join(tmp_dir, "#{Random::Secure.hex(12)}.cr")
      source_body = File.read(source).lines.reject { |line| line.includes?("extension_api") && line.strip.starts_with?("require") }.join("\n")
      File.write(tmp_path, File.read(sdk_path) + "\n" + source_body)

      status = Process.run(crystal_command, ["run", tmp_path], input: stdin, output: stdout, error: stderr)
      status.exit_code
    rescue ex
      stderr.puts ex.message
      1
    ensure
      File.delete(tmp_path) if tmp_path && File.exists?(tmp_path)
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
      tool_ref = argv[0]?.try { |arg| normalize_tool_ref_arg(arg) }
      unless tool_ref
        stderr.puts "missing @<tool_ref>"
        return 1
      end

      # Optional detailed help:
      #   actra help @<tool_ref> [method] <path_tokens...>
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

    private def self.run_query(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]?.try { |arg| normalize_tool_ref_arg(arg) } || raise "missing @<tool_ref>"
      args = argv[1..]
      args = args[1..] if args[0]? == "--"

      case args[0]?
      when nil
        run_help([tool_ref], stdout, stderr)
      when "help", "info"
        run_help([tool_ref] + args[1..], stdout, stderr)
      when "docs", "doc"
        run_docs([tool_ref] + args[1..], stdout, stderr)
      when "launch", "run"
        run_launch([tool_ref] + args[1..], stdin, stdout, stderr)
      else
        run_help([tool_ref] + args, stdout, stderr)
      end
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_docs(argv : Array(String), stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]?.try { |arg| normalize_tool_ref_arg(arg) } || raise "missing @<tool_ref>"
      out_path = nil.as(String?)
      op_method = nil.as(String?)
      op_tokens = [] of String
      i = 1
      while i < argv.size
        arg = argv[i]
        if arg == "--out"
          out_path = argv[i + 1]? || raise "missing value for --out"
          i += 2
        elsif arg.starts_with?("--out=")
          out_path = arg.split("=", 2)[1]
          i += 1
        elsif op_method.nil? && http_method_token?(arg)
          op_method = arg.downcase
          i += 1
        else
          op_tokens << arg
          i += 1
        end
      end

      body = docs_markdown(tool_ref, op_method, op_tokens)
      if path = out_path
        FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
        File.write(path, body)
        stdout.puts "wrote: #{path}"
      else
        stdout.print body
      end
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.docs_markdown(tool_ref : String, op_method : String?, op_tokens : Array(String)) : String
      cfg = Config.load
      resolved = ToolResolver.resolve(tool_ref, cfg)
      doc = OpenAPI::Loader.load_any(resolved.api_url)
      base = OpenAPI::BaseUrl.compute(doc, tool_ref)
      builder = OpenAPI::Dto::Builder.new(doc)

      String.build do |io|
        io.puts "# #{tool_ref}"
        io.puts
        io.puts "- Source: `#{resolved.source}`"
        io.puts "- OpenAPI: `#{doc.version_string}`"
        io.puts "- Base URL: `#{base}`"

        if op_tokens.any?
          method = op_method || "get"
          op = OpenAPI::Router.match(doc, method, resolved.manifest.expand_path_tokens(op_tokens))
          dto = builder.operation(op.method, op.path_template)
          docs_operation(io, dto)
        else
          io.puts
          io.puts "## Operations"
          builder.list_operations.each do |item|
            summary = item.summary ? " - #{item.summary}" : ""
            io.puts "- `#{item.method.upcase} #{item.path_template}`#{summary}"
          end
        end

        if resolved.manifest.path_aliases.any?
          io.puts
          io.puts "## Path Aliases"
          resolved.manifest.path_aliases.each do |k, v|
            io.puts "- `#{k}` -> `#{v}`"
          end
        end
      end
    end

    private def self.docs_operation(io : IO, dto : OpenAPI::Dto::Operation) : Nil
      io.puts
      io.puts "## `#{dto.method.upcase} #{dto.path_template}`"
      if dto.summary
        io.puts
        io.puts dto.summary
      end
      if dto.description
        io.puts
        io.puts dto.description
      end

      if dto.parameters.any?
        io.puts
        io.puts "### Parameters"
        dto.parameters.each do |p|
          ty = p.schema.try(&.type) || "unknown"
          req = p.required ? "required" : "optional"
          desc = p.description ? " - #{p.description}" : ""
          io.puts "- `#{p.location}.#{p.name}`: #{ty}, #{req}#{desc}"
        end
      end

      if rb = dto.request_body_json
        io.puts
        io.puts "### Request Body"
        io.puts
        io.puts "- Content-Type: `#{rb.content_type}`"
        fields = Interactive::FormBuilder.fields_for_schema(rb.schema)
        if fields.any?
          io.puts
          io.puts "### Interactive Fields"
          fields.each do |f|
            extra = f.kind == Render::FieldKind::Enum ? ", values: #{f.enum_values.join(", ")}" : ""
            io.puts "- `#{f.pointer}`: #{f.kind.to_s.downcase}, required: #{f.required}#{extra}"
          end
        end
      end
    end

    private def self.run_ain(argv : Array(String), stdout : IO, stderr : IO) : Int32
      tool_ref = argv[0]?.try { |arg| normalize_tool_ref_arg(arg) }
      unless tool_ref
        stderr.puts "missing @<tool_ref>"
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
      if argv[0]? == "shell"
        shell = argv[1]?
        unless shell
          stderr.puts "missing <bash|zsh>"
          return 1
        end
        stdout.puts Activation.auth_script(shell)
        return 0
      end

      tool_ref = argv[0]?.try { |arg| normalize_tool_ref_arg(arg) }
      unless tool_ref
        stderr.puts "missing @<tool_ref> or shell"
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

    def self.run_request(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      tool_ref = normalize_tool_ref_arg(argv[0])
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
      interactive_disable : Bool,
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

      raise "no interactive schema for #{op_key}; provide --json or configure config.rcl render.operations" if fields.empty?

      b = Interactive::JsonBuilder.new
      fields.each do |f|
        value_any : JSON::Any = case f.kind
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

      ensure_default_config

      installed = false
      tool_refs = [] of String
      argv[1..].each do |a|
        if a == "--installed"
          installed = true
        else
          tool_refs << normalize_tool_ref_arg(a)
        end
      end

      if installed
        Lock.load.ains.keys.each { |k| tool_refs << k }
      end
      tool_refs = tool_refs.uniq
      if tool_refs.empty?
        stderr.puts "no tools provided (use: actra shell #{shell} @<tool_ref>... or --installed)"
        return 1
      end

      tool_refs.each do |ref|
        name = ToolKey.for(ref)
        if name.empty? || name.matches?(/\s/) || name.includes?('=') || name.includes?('/')
          raise "invalid alias name: #{name}"
        end
        stdout.puts "alias #{name}=#{shell_sq("actra @#{ref}")}"
        stdout.puts "alias '?#{name}'=#{shell_sq("actra query @#{ref}")}"
      end
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_launch(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      mode = nil.as(String?)
      remote = ENV["ACTRA_LAUNCH_REMOTE"]? || "@remote@lefine.pro"
      image = ENV["ACTRA_LAUNCH_IMAGE"]? || ENV["ACTRA_CONTAINER_IMAGE"]?
      runtime = ENV["ACTRA_LAUNCH_RUNTIME"]? || ENV["ACTRA_CONTAINER_RUNTIME"]? || "docker"
      dry_run = false
      command_argv = [] of String
      after_separator = false
      i = 0
      while i < argv.size
        arg = argv[i]
        if after_separator
          command_argv << arg
          i += 1
        elsif arg == "--"
          after_separator = true
          i += 1
        elsif arg == "--mode"
          mode = argv[i + 1]? || raise "missing value for --mode"
          i += 2
        elsif arg.starts_with?("--mode=")
          mode = arg.split("=", 2)[1]
          i += 1
        elsif arg == "--remote"
          remote = argv[i + 1]? || raise "missing value for --remote"
          i += 2
        elsif arg.starts_with?("--remote=")
          remote = arg.split("=", 2)[1]
          i += 1
        elsif arg == "--image"
          image = argv[i + 1]? || raise "missing value for --image"
          i += 2
        elsif arg.starts_with?("--image=")
          image = arg.split("=", 2)[1]
          i += 1
        elsif arg == "--runtime"
          runtime = argv[i + 1]? || raise "missing value for --runtime"
          i += 2
        elsif arg.starts_with?("--runtime=")
          runtime = arg.split("=", 2)[1]
          i += 1
        elsif arg == "--dry-run"
          dry_run = true
          i += 1
        else
          command_argv << arg
          i += 1
        end
      end

      tool = command_argv[0]? || raise "missing tool"
      args = command_argv[1..]
      selected = mode || select_launch_mode(stdin, stdout)

      case selected
      when "remote", "remote-lefine", "lefine"
        run_launch_remote(remote, tool, args, stdin, stdout, stderr, dry_run)
      when "container"
        run_launch_container(image, runtime, tool, args, stdin, stdout, stderr, dry_run)
      when "background", "bg"
        run_launch_background(tool, args, stdout, stderr, dry_run)
      when "assistant", "agent"
        run_launch_assistant(tool, args, stdin, stdout, stderr, dry_run)
      when "run", "local"
        run_launch_local(tool, args, stdin, stdout, stderr, dry_run)
      else
        stderr.puts "unknown launch mode: #{selected}"
        1
      end
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.select_launch_mode(stdin : IO, stdout : IO) : String
      raise "missing --mode when stdin is not a TTY" unless stdin.tty?
      Interactive::Prompt.ask_enum(stdin, stdout, "Launch mode", ["background", "assistant", "run", "remote-lefine", "container"], Config.load.render)
    end

    private def self.run_at_menu(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      return run_at_search(argv, stdin, stdout, stderr) if {"--action", "--action-preview", "--mode-preview"}.includes?(argv[0]?)
      return run_at_search(argv, stdin, stdout, stderr) if at_search_invocation?(argv)

      run_launch(argv, stdin, stdout, stderr)
    end

    private def self.agent_action_argv(action : AtMenuActionConfig, argv : Array(String)) : Array(String)
      result = [] of String
      if provider = action.provider
        result += ["--provider", provider] unless argv.includes?("--provider")
      end

      if model = action.model
        result += ["--model", model] unless argv.includes?("--model")
      end

      unless action.prompt_modes.empty? || argv.includes?("--prompt") || argv.includes?("--prompt-mode")
        action.prompt_modes.each { |mode| result += ["--prompt", mode] }
      end
      result + argv
    end

    private def self.run_at_action(action : AtMenuActionConfig, text : String, stdin : IO, stdout : IO, stderr : IO) : Int32
      return missing_action_text(stderr) if text.empty?
      case action.kind
      when "agent"
        run_agent(parse_agent_options(agent_action_argv(action, [text])), stdin, stdout, stderr)
      when "org_todo"
        create_org_todo(action, text, stdout)
      else
        raise "unsupported @ action kind: #{action.kind}"
      end
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.missing_action_text(stderr : IO) : Int32
      stderr.puts "missing text for action"
      1
    end

    private def self.create_org_todo(action : AtMenuActionConfig, text : String, stdout : IO) : Int32
      path = action.org_todo_path || raise "org_todo_path is required for @ action #{action.name}"
      clean = text.lines.map(&.strip).reject(&.empty?).join(" ")
      raise "empty TODO text" if clean.empty?

      FileUtils.mkdir_p(File.dirname(path))
      append_org_todo(path, action.category, action.executor, clean)
      stdout.puts "created TODO: #{path}"
      0
    end

    private def self.append_org_todo(path : String, category : String?, executor : String?, text : String) : Nil
      category_name = category
      if category_name.nil? || category_name.empty?
        File.open(path, "a") { |file| write_org_todo(file, "*", text, executor) }
        return
      end

      heading = "* #{category_name}"
      if File.exists?(path)
        existing = File.read(path)
        if existing.lines.any? { |line| line.strip == heading }
          File.open(path, "a") do |file|
            file.puts unless existing.ends_with?("\n")
            write_org_todo(file, "**", text, executor)
          end
        else
          File.open(path, "a") do |file|
            file.puts unless existing.empty? || existing.ends_with?("\n")
            file.puts heading
            write_org_todo(file, "**", text, executor)
          end
        end
      else
        File.open(path, "w") do |file|
          file.puts heading
          write_org_todo(file, "**", text, executor)
        end
      end
    end

    private def self.write_org_todo(file : IO, stars : String, text : String, executor : String?) : Nil
      file.puts "#{stars} TODO #{text}"
      return if executor.nil? || executor.empty?

      file.puts ":PROPERTIES:"
      file.puts ":EXECUTOR: #{executor}"
      file.puts ":END:"
    end

    private def self.at_search_invocation?(argv : Array(String)) : Bool
      return true if argv.empty?
      !argv.any? { |arg| arg == "--" || arg == "--mode" || arg.starts_with?("--mode=") || arg == "--remote" || arg.starts_with?("--remote=") || arg == "--image" || arg.starts_with?("--image=") || arg == "--runtime" || arg.starts_with?("--runtime=") || arg == "--dry-run" }
    end

    private def self.run_at_search(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      if argv[0]? == "--action-preview"
        action = argv[1]? || raise "missing action for --action-preview"
        return run_at_action_preview(action, argv[2..], stdout, stderr)
      end

      if argv[0]? == "--action"
        action = argv[1]? || raise "missing action for --action"
        return run_at_selected_action(action, argv[2..], stdin, stdout, stderr)
      end

      if argv[0]? == "--mode-preview"
        mode = argv[1]? || raise "missing mode for --mode-preview"
        return run_at_action_preview(mode, argv[2..], stdout, stderr) if at_action?(mode)
        return run_at_mode_preview(mode, argv[2..], stdout, stderr)
      end

      query = argv.join(" ").strip
      entries = at_launcher_entries

      if entry = selected_at_entry(argv, entries)
        rest = argv[1..].join(" ").strip
        return run_selected_at_entry(entry, rest, stdin, stdout, stderr)
      end
      if action = at_shorthand_action(argv[0]?)
        return run_at_selected_action(action, argv[1..], stdin, stdout, stderr)
      end

      unless query.empty?
        return run_agent(parse_agent_options(argv), stdin, stdout, stderr)
      end

      matches = matching_at_entries(entries, query)
      if matches.empty?
        stderr.puts "no @ results"
        return 1
      end

      matches.first(20).each { |entry| stdout.puts entry.row }
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_at_mode_preview(mode : String, argv : Array(String), stdout : IO, stderr : IO) : Int32
      query = argv.join(" ").strip
      entries = matching_at_entries(at_entries_for_mode(mode), query)

      if entries.empty?
        if launch_mode?(mode)
          stdout.puts at_launcher_row("mode", "#{mode}: #{query.empty? ? "missing command" : command_line(argv)}")
          return 0
        end

        stderr.puts "no @ results"
        return 1
      end

      entries.first(20).each { |entry| stdout.puts entry.row }
      0
    end

    private def self.run_at_action_preview(action : String, argv : Array(String), stdout : IO, stderr : IO) : Int32
      normalized = normalize_at_action(action)
      raise "unknown @ action: #{action}" unless at_action?(normalized)

      query = argv.join(" ").strip
      if action_config = at_menu_action?(action)
        preview = query.empty? ? "create TODO: #{action_config.label}" : "create TODO: #{action_config.label} #{query}"
        stdout.puts at_launcher_row("action", "#{normalized}: #{preview}")
        return 0
      end

      preview =
        case normalized
        when "agent"
          query.empty? ? "missing task" : "actra agent #{command_line(argv)}"
        else
          query.empty? ? "missing command" : command_line(argv)
        end
      stdout.puts at_launcher_row("action", "#{normalized}: #{preview}")
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.run_at_selected_action(action : String, argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      normalized = normalize_at_action(action)
      raise "unknown @ action: #{action}" unless at_action?(normalized)

      case normalized
      when "agent"
        task = argv.join(" ").strip
        return missing_action_text(stderr) if task.empty?
        run_agent(parse_agent_options(argv), stdin, stdout, stderr)
      when "run", "background", "remote", "container"
        run_launch(["--mode", normalized] + argv, stdin, stdout, stderr)
      else
        if action_config = at_menu_action?(action)
          task = argv.join(" ").strip
          return missing_action_text(stderr) if task.empty?
          return run_at_action(action_config, task, stdin, stdout, stderr)
        end
        stderr.puts "unsupported @ action: #{action}"
        1
      end
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.at_menu_action?(action : String) : AtMenuActionConfig?
      Config.load.at.menu_actions.find { |candidate| candidate.name == action || candidate.label == action }
    end

    private def self.run_selected_at_entry(entry : AtLauncherEntry, text : String, stdin : IO, stdout : IO, stderr : IO) : Int32
      case entry.kind
      when "actor"
        if text.empty?
          stdout.puts entry.value
          0
        else
          Dispatch.run(["--command", entry.value, "--", text], stdin, stdout, stderr)
        end
      when "action"
        action = Config.load.at.menu_actions.find { |candidate| candidate.label == entry.value }
        raise "unknown @ action: #{entry.value}" unless action
        run_at_action(action, text, stdin, stdout, stderr)
      when "agent"
        if text.empty?
          stdout.puts entry.value
          0
        else
          run_agent(parse_agent_options(["--provider", entry.value, text]), stdin, stdout, stderr)
        end
      when "model"
        if text.empty?
          stdout.puts entry.value
          0
        else
          run_agent(parse_agent_options(["--model", entry.value, text]), stdin, stdout, stderr)
        end
      when "file"
        run_at_file_action_menu(entry.value, stdin, stdout, stderr)
      else
        stderr.puts "unsupported @ target: #{entry.kind}"
        1
      end
    end

    private struct AtLauncherEntry
      getter kind : String
      getter value : String
      getter row : String

      def initialize(@kind : String, @value : String, @row : String)
      end
    end

    private def self.at_launcher_entries : Array(AtLauncherEntry)
      actor_completion_candidates.reject { |actor| actor == "@" }.map { |actor| AtLauncherEntry.new("actor", actor, at_launcher_row("actor", actor)) } +
        agent_launcher_entries +
        model_launcher_entries +
        Config.load.at.menu_actions.map { |action| AtLauncherEntry.new("action", action.label, at_launcher_row("action", action.label)) } +
        Interactive::PickerTui.file_context_candidates.map do |token|
          path = token.starts_with?("@") ? token[1..] : token
          AtLauncherEntry.new("file", path, at_launcher_row("file", path))
        end
    end

    private def self.at_launcher_row(kind : String, value : String) : String
      "#{kind.ljust(7)} #{value}"
    end

    private def self.agent_launcher_entries : Array(AtLauncherEntry)
      cfg = Config.load
      cfg.providers.keys.sort.map do |provider|
        label = provider == cfg.default_provider ? "#{provider} (default)" : provider
        AtLauncherEntry.new("agent", provider, at_launcher_row("agent", label))
      end
    end

    private def self.model_launcher_entries : Array(AtLauncherEntry)
      cfg = Config.load
      default_provider = cfg.provider
      default_model = cfg.default_model || default_provider.try(&.default_model) || ENV["ACTRA_MODEL"]? || Config::DEFAULT_MODEL
      models = [Config::DEFAULT_MODEL, default_model] of String

      cfg.providers.each_value do |provider|
        if provider.models.empty?
          if model = provider.default_model
            models << model
          end
        else
          provider.models.each_key { |model| models << model }
        end
      end

      models.uniq.sort.map do |model|
        label = model == default_model ? "#{model} (default)" : model
        AtLauncherEntry.new("model", model, at_launcher_row("model", label))
      end
    end

    private def self.at_entries_for_mode(mode : String) : Array(AtLauncherEntry)
      normalized = normalize_at_mode(mode)
      entries = at_launcher_entries
      case normalized
      when "file"
        entries.select { |entry| entry.kind == "file" }
      when "actions"
        entries.select { |entry| entry.kind == "action" }
      when "agents", "agent"
        entries.select { |entry| entry.kind == "agent" }
      when "models", "model"
        entries.select { |entry| entry.kind == "model" }
      when "run", "background", "remote", "container"
        [] of AtLauncherEntry
      else
        entries
      end
    end

    private def self.normalize_at_mode(mode : String) : String
      case mode
      when "files", "file-search", "file_search"
        "file"
      when "context", "contexts"
        "file"
      when "action", "actions-search", "actions_search"
        "actions"
      when "local"
        "run"
      when "bg"
        "background"
      when "remote-lefine", "lefine"
        "remote"
      else
        mode
      end
    end

    private def self.launch_mode?(mode : String) : Bool
      {"run", "background", "remote", "container"}.includes?(normalize_at_mode(mode))
    end

    private def self.at_action?(action : String) : Bool
      normalized = normalize_at_action(action)
      return true if {"agent", "run", "background", "remote", "container"}.includes?(normalized)
      !!at_menu_action?(action)
    end

    private def self.normalize_at_action(action : String) : String
      case action
      when "local"
        "run"
      when "bg"
        "background"
      when "remote-lefine", "lefine"
        "remote"
      else
        action
      end
    end

    private def self.at_shorthand_action(token : String?) : String?
      return nil unless token
      return nil unless token.starts_with?("@")
      action = token[1..]
      return nil if action.empty?
      return nil unless {"agent", "run", "background", "remote", "container"}.includes?(action)
      normalize_at_action(action)
    end

    private def self.selected_at_entry(argv : Array(String), entries : Array(AtLauncherEntry)) : AtLauncherEntry?
      first = argv[0]?
      return nil unless first

      entries.find do |entry|
        case entry.kind
        when "actor"
          entry.value == first
        when "file"
          first == "@#{entry.value}" || first == entry.value
        when "action"
          entry.value == first
        when "agent"
          entry.value == first || first == "agent:#{entry.value}"
        when "model"
          entry.value == first || first == "model:#{entry.value}"
        else
          false
        end
      end
    end

    private def self.matching_at_entries(entries : Array(AtLauncherEntry), query : String) : Array(AtLauncherEntry)
      clean = query.downcase
      return entries if clean.empty?

      entries.select do |entry|
        entry.value.downcase.includes?(clean) ||
          entry.row.downcase.includes?(clean) ||
          (entry.kind == "file" && "@#{entry.value}".downcase.includes?(clean))
      end
    end

    private def self.run_launch_remote(remote : String, tool : String, args : Array(String), stdin : IO, stdout : IO, stderr : IO, dry_run : Bool) : Int32
      content = String.build do |io|
        io.puts "Run this tool remotely with Lefine."
        io.puts
        io.puts "Command:"
        io.puts command_line([tool] + args)
      end
      dispatch_args = ["--command", remote]
      dispatch_args << "--dry-run" if dry_run
      Dispatch.run(dispatch_args + ["--", content], stdin, stdout, stderr)
    end

    private def self.run_launch_container(image : String?, runtime : String, tool : String, args : Array(String), stdin : IO, stdout : IO, stderr : IO, dry_run : Bool) : Int32
      container_image = image || raise "container mode requires --image or ACTRA_LAUNCH_IMAGE"
      runtime_command = container_runtime_command(runtime)
      unless dry_run || Process.find_executable(runtime_command)
        raise "container runtime not found: #{runtime_command} (set --runtime, ACTRA_LAUNCH_RUNTIME, or ACTRA_CONTAINER_RUNTIME)"
      end

      container_args = ["run", "--rm", "-i", "-v", "#{Dir.current}:#{Dir.current}", "-w", Dir.current, container_image, tool] + args

      if dry_run
        stdout.puts command_line([runtime_command] + container_args)
        return 0
      end

      status = Process.run(runtime_command, container_args, input: stdin, output: stdout, error: stderr)
      if status.exit_code != 0
        stderr.puts container_runtime_hint(runtime_command)
      end
      status.exit_code
    end

    private def self.container_runtime_command(runtime : String) : String
      normalized = runtime.strip.downcase
      raise "container runtime cannot be empty" if normalized.empty?

      case normalized
      when "docker", "podman", "nerdctl"
        normalized
      when "containerd"
        "nerdctl"
      else
        runtime.strip
      end
    end

    private def self.container_runtime_hint(runtime : String) : String
      case runtime
      when "docker"
        "container mode could not run docker. Check access to /var/run/docker.sock or use --runtime podman, --runtime nerdctl, or ACTRA_CONTAINER_RUNTIME."
      when "podman"
        "container mode could not run podman. Check podman is installed and the current user can run containers."
      when "nerdctl"
        "container mode could not run nerdctl/containerd. Check nerdctl is installed and containerd is running."
      else
        "container mode could not run #{runtime}. Check the runtime command and permissions."
      end
    end

    private def self.run_launch_assistant(tool : String, args : Array(String), stdin : IO, stdout : IO, stderr : IO, dry_run : Bool) : Int32
      command_path = Process.find_executable(tool) || tool
      prompt = String.build do |io|
        io.puts "Inspect this command and explain how to use it safely."
        io.puts
        io.puts "Command path: #{command_path}"
        io.puts "Command line: #{command_line([tool] + args)}"
      end

      if dry_run
        stdout.puts "ASSISTANT"
        stdout.puts prompt
        return 0
      end

      opts = AgentOptions.new
      opts.prompt_args = [prompt]
      Agent.run(opts, stdin, stdout, stderr)
    end

    private def self.run_launch_local(tool : String, args : Array(String), stdin : IO, stdout : IO, stderr : IO, dry_run : Bool) : Int32
      if dry_run
        stdout.puts command_line([tool] + args)
        return 0
      end

      status = Process.run(tool, args, input: stdin, output: stdout, error: stderr)
      status.exit_code
    end

    private def self.run_launch_background(tool : String, args : Array(String), stdout : IO, stderr : IO, dry_run : Bool) : Int32
      FileUtils.mkdir_p(launch_dir)
      id = "#{Time.utc.to_s("%Y%m%d%H%M%S")}-#{Random::Secure.hex(4)}"
      log_path = File.join(launch_dir, "#{id}.log")
      pid_path = File.join(launch_dir, "#{id}.pid")
      shell_command = "nohup #{command_line([tool] + args)} > #{shell_sq(log_path)} 2>&1 < /dev/null & echo $! > #{shell_sq(pid_path)}"

      if dry_run
        stdout.puts shell_command
        stdout.puts "log: #{log_path}"
        stdout.puts "pid: #{pid_path}"
        return 0
      end

      status = Process.run("/bin/sh", ["-c", shell_command], output: Process::Redirect::Close, error: stderr)
      return status.exit_code unless status.success?

      pid = File.exists?(pid_path) ? File.read(pid_path).strip : ""
      stdout.puts "started: #{pid}"
      stdout.puts "log: #{log_path}"
      0
    end

    private def self.launch_dir : String
      File.join(Xdg.cache_dir, "launches")
    end

    private def self.run_activate(argv : Array(String), stdout : IO, stderr : IO) : Int32
      install = false
      shell = nil.as(String?)

      argv.each do |arg|
        if arg == "--install"
          install = true
        else
          shell = arg
        end
      end

      unless shell
        stderr.puts "missing <bash|zsh>"
        return 1
      end

      unless shell == "bash" || shell == "zsh"
        stderr.puts "unsupported shell: #{shell} (expected bash or zsh)"
        return 1
      end

      ensure_default_config

      if install
        path = Activation.install(shell.not_nil!)
        stdout.puts "installed: #{path}"
      else
        stdout.puts Activation.script(shell.not_nil!)
      end
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.ensure_default_config : Nil
      return if File.exists?(Xdg.config_path) || File.exists?(Xdg.legacy_astra_config_path)

      path = Xdg.config_write_path
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, default_rcl_config)
    end

    private def self.run_config(argv : Array(String), stdout : IO, stderr : IO) : Int32
      case argv[0]?
      when "init"
        path = Xdg.config_write_path
        FileUtils.mkdir_p(File.dirname(path))
        if File.exists?(path)
          stderr.puts "config already exists: #{path}"
          return 1
        end
        File.write(path, default_rcl_config)
        stdout.puts "created: #{path}"
        0
      when "validate"
        Config.load
        stdout.puts "ok"
        0
      when "migrate", "update"
        migrate_config(stdout, stderr)
      when "print"
        cfg = Config.load
        stdout.puts "config: #{Xdg.config_load_path}"
        stdout.puts "default_server: #{cfg.default_server}"
        stdout.puts "servers:"
        cfg.servers.each do |name, server|
          stdout.puts "  - #{name} #{server.base_url} actors=#{server.actors.map(&.name).join(",")}"
        end
        stdout.puts "default_provider: #{cfg.default_provider}"
        stdout.puts "providers:"
        cfg.providers.each do |name, provider|
          stdout.puts "  - #{name} api=#{provider.api} base_url=#{provider.base_url}"
        end
        stdout.puts "session_dir: #{cfg.session_dir}"
        stdout.puts "permissions: mode=#{cfg.permissions.mode.config_value} sandbox=#{cfg.permissions.sandbox} rules=#{cfg.permissions.tools.size}"
        cfg.permissions.tools.each do |rule|
          stdout.puts "  - #{rule.tool} allow=#{rule.allow.join(",")} ask=#{rule.ask.join(",")} deny=#{rule.deny.join(",")}"
        end
        stdout.puts "extensions: #{cfg.extensions.map(&.name).join(",")}"
        stdout.puts "filetypes: #{cfg.file_editors.map(&.name).join(",")}"
        stdout.puts "at.menu_actions: #{cfg.at.menu_actions.map(&.name).join(",")}"
        0
      else
        stderr.puts "usage: actra config <init|validate|print|migrate|update>"
        1
      end
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.migrate_config(stdout : IO, stderr : IO) : Int32
      current = Xdg.config_path
      legacy = Xdg.legacy_astra_config_path

      if File.exists?(current)
        Config.load
        stdout.puts "config already current: #{current}"
        return 0
      end

      unless File.exists?(legacy)
        FileUtils.mkdir_p(File.dirname(current))
        File.write(current, default_rcl_config)
        Config.load
        stdout.puts "created: #{current}"
        return 0
      end

      FileUtils.mkdir_p(File.dirname(current))
      File.write(current, File.read(legacy))
      Config.load
      stdout.puts "migrated: #{legacy} -> #{current}"
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

    private def self.command_line(argv : Array(String)) : String
      argv.map { |arg| shell_sq(arg) }.join(" ")
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
      actra (v0.1)

      Commands:
        actra activate <bash|zsh> [--install]
        actra config <init|validate|print|migrate|update>
        actra dispatch --command @name|@actor@domain -- [args...]
        actra query @<tool_ref> [help|docs|launch] [args...]
        actra launch [--mode background|assistant|run|remote-lefine|container] @<tool_ref> [args...]
        actra agent [-p] [--mode text|json|rpc] [--prompt code|plan|review|debug|ask] [--provider NAME] [--model MODEL] [--permission-mode standard|restrictive|accept|accept-all|yolo] [--permission-state] [--permission-allow TOOL:PATTERN] [--permission-deny TOOL:PATTERN] [--permission-revoke TOOL:PATTERN] [--permission-clear] [--sandbox] [@paths...] [prompt...]
        actra -p [--prompt code|plan|review|debug|ask] [--provider NAME] [--model MODEL] [--permission-mode standard|restrictive|accept|accept-all|yolo] [@paths...] [prompt...]
        actra @ <query...>       # quick results, or Tab/Shift+Tab action menu after activation
        actra complete <at|actors> [prefix]
        actra package <install|remove|update|list|config> ...
        actra shell <bash|zsh> [--installed] @<tool_ref>...
        actra oas validate <file_or_url>
        actra help @<tool_ref> [method] <path_tokens...>
        actra ain @<tool_ref>
        actra auth @<tool_ref> --bearer TOKEN
        actra auth shell <bash|zsh>
        actra @<tool_ref> [method] <path_tokens...> [key=value...] [--json STR] [--header k:v] [--render MODE] [--out PATH] [--interactive|--no-interactive] [--dry-run]

      Render MODE:
        auto|table|json|raw

      JSON bodies:
        --json STR             Inline JSON string
        --json @path.json      Read JSON from file
        --json @               Pick a JSON file (interactive picker, otherwise prompts for a path)
      TXT
      1
    end

    private def self.version(io : IO) : Int32
      io.puts "actra 0.1.0"
      0
    end

    private def self.default_rcl_config : String
      <<-RCL
      base do
        db_path = "$HOME/.cache/actra/actra.db"
        install_dir = "$HOME/.local/bin"
        session_dir = "$HOME/.cache/actra/sessions"
        default_provider = "openai"
        default_model = "@auto@lefine.pro"
      end

      uri_schemes do
        registry = "https://actra.ofs.lol"
      end

      provider "openai" do
        api = "openai-responses"
        base_url = "https://api.openai.com/v1"
        api_key = "OPENAI_API_KEY"
        auth_header = true
        default_model = "gpt-4.1-mini"
      end

      provider "ollama" do
        api = "openai-chat"
        base_url = "http://127.0.0.1:11434/v1"
        auth_header = false
        default_model = "llama3.1:8b"
      end

      provider "llama.cpp" do
        api = "openai-chat"
        base_url = "http://127.0.0.1:8080/v1"
        auth_header = false
        default_model = "local"
      end

      provider "llamacpp" do
        api = "openai-chat"
        base_url = "http://127.0.0.1:8080/v1"
        auth_header = false
        default_model = "local"
      end

      permissions do
        default_mode = "standard"
        sandbox = false
        doom_loop_threshold = 8

        tool "bash" do
          ask = ["**"]
        end
      end

      filetype "code" do
        extensions = [".cr", ".rb", ".py", ".js", ".ts", ".go", ".rs"]
        editor = "nvim"
      end

      filetype "markdown" do
        extensions = [".md", ".markdown", ".org"]
        editor = "nvim"
      end

      filetype "images" do
        patterns = ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp"]
        editor = "xdg-open"
      end
      RCL
    end
  end
end
