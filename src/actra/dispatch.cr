require "option_parser"

require "./config"
require "./forgefed"

module Actra
  module Dispatch
    def self.run(argv : Array(String), stdin : IO, stdout : IO, stderr : IO) : Int32
      command = nil.as(String?)
      dry_run = false

      parser = OptionParser.new do |p|
        p.on("--command CMD", "Shell command token, for example @code or @actor@domain") { |value| command = value }
        p.on("--dry-run", "Print the resolved dispatch instead of sending it") { dry_run = true }
      end
      parser.parse(argv)

      raise "missing --command" unless command
      cmd = command.not_nil!
      args = argv
      args = args[1..] if args[0]? == "--"
      cfg = Config.load

      if cmd == "@claude"
        return local_cli_task("claude", ENV["ACTRA_CLAUDE_CLI"]? || "claude", ["-p"], args, stdin, stdout, stderr, dry_run)
      end

      if cmd == "@codex"
        return local_cli_task("codex", ENV["ACTRA_CODEX_CLI"]? || "codex", ["exec"], args, stdin, stdout, stderr, dry_run)
      end

      if route = cfg.actor_for_command(cmd)
        server, actor = route
        return forgefed_task(server, actor, args, stdin, stdout, stderr, dry_run)
      end

      if handle = actor_handle(cmd)
        actor_name, domain = handle
        return fediverse_actor_inbox(cfg, actor_name, domain, args, stdin, stdout, stderr, dry_run)
      end

      if cmd.starts_with?("@")
        tool_ref = cmd[1..]
        return CLI.run_request([tool_ref] + args, stdin, stdout, stderr)
      end

      stderr.puts "unsupported dispatch command: #{cmd}"
      1
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.forgefed_task(server : ServerConfig, actor : ActorConfig, args : Array(String), stdin : IO, stdout : IO, stderr : IO, dry_run : Bool) : Int32
      content = prompt_from(args, stdin)
      if content.empty?
        stderr.puts "missing task text"
        return 1
      end

      delivery = ForgeFed.build_ticket_activity(server, actor, actor.name, content, sign: !dry_run)
      if dry_run
        stdout.puts delivery.dry_run
        return 0
      end

      response = ForgeFed.post(delivery)
      stdout.puts response.body
      response.status_code >= 200 && response.status_code < 300 ? 0 : 1
    end

    private def self.local_cli_task(name : String, command : String, prefix_args : Array(String), args : Array(String), stdin : IO, stdout : IO, stderr : IO, dry_run : Bool) : Int32
      content = prompt_from(args, stdin)
      if content.empty?
        stderr.puts "missing task text"
        return 1
      end

      cli_args = prefix_args + [content]
      if dry_run
        stdout.puts "LOCAL #{name}"
        stdout.puts command_line([command] + cli_args)
        return 0
      end

      unless Process.find_executable(command) || command.includes?("/")
        stderr.puts "missing #{name} CLI: #{command}"
        return 127
      end

      status = Process.run(command, cli_args, output: stdout, error: stderr)
      status.exit_code
    end

    private def self.fediverse_actor_inbox(cfg : Config, actor_name : String, domain : String, args : Array(String), stdin : IO, stdout : IO, stderr : IO, dry_run : Bool) : Int32
      default_server = cfg.server || ServerConfig.new(
        domain,
        "https://#{domain}",
        "https://#{domain}/actor/shell",
        "/inbox",
        "/outbox",
        nil,
        [] of ActorConfig
      )
      server = ServerConfig.new(
        domain,
        "https://#{domain}",
        default_server.actor_id,
        "/inbox",
        default_server.outbox,
        default_server.http_signature,
        [] of ActorConfig
      )

      content = prompt_from(args, stdin)
      if content.empty?
        stderr.puts "missing task text"
        return 1
      end

      inbox = "/users/#{actor_name}/inbox"
      delivery = ForgeFed.build_ticket_activity(server, nil, "@#{actor_name}@#{domain}", content, inbox, sign: !dry_run)
      if dry_run
        stdout.puts delivery.dry_run
        return 0
      end

      response = ForgeFed.post(delivery)
      stdout.puts response.body
      response.status_code >= 200 && response.status_code < 300 ? 0 : 1
    end

    private def self.prompt_from(args : Array(String), stdin : IO) : String
      text = args.join(" ").strip
      piped = stdin.tty? ? "" : stdin.gets_to_end.strip

      if piped.empty?
        text
      elsif text.empty?
        piped
      else
        "#{text}\n\n#{piped}"
      end
    end

    private def self.actor_handle(cmd : String) : Tuple(String, String)?
      return nil unless cmd.starts_with?("@")
      return nil if cmd.includes?("/")

      parts = cmd[1..].split("@", 2)
      return nil unless parts.size == 2

      actor = parts[0].strip
      domain = parts[1].strip
      return nil if actor.empty? || domain.empty?
      return nil if actor.includes?("/") || domain.includes?("/")

      {actor, domain}
    end

    private def self.command_line(argv : Array(String)) : String
      argv.map { |arg| shell_sq(arg) }.join(" ")
    end

    private def self.shell_sq(s : String) : String
      "'" + s.gsub("'", %q('"'"')) + "'"
    end
  end
end
