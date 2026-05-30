require "json"

require "./config"
require "./xdg"

module Actra
  class ExtensionRuntime
    def self.for_config(cfg : Config, explicit : Array(String), enabled : Bool) : ExtensionRuntime
      extensions = [] of ExtensionConfig
      extensions.concat(cfg.extensions) if enabled
      extensions.concat(discover) if enabled
      explicit.each { |source| extensions << from_source(source) }
      new(extensions)
    end

    def initialize(@extensions : Array(ExtensionConfig))
    end

    def emit(event : String, payload : JSON::Any) : JSON::Any
      current = payload
      @extensions.each do |extension|
        next unless extension.handles?(event)
        next_value = run_extension(extension, event, current)
        current = next_value if next_value
      end
      current
    end

    private def run_extension(extension : ExtensionConfig, event : String, payload : JSON::Any) : JSON::Any?
      input = JSON.build do |json|
        json.object do
          json.field "extension", extension.name
          json.field "event", event
          json.field "payload", payload
        end
      end

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(
        "/bin/sh",
        ["-c", extension.command],
        input: IO::Memory.new(input),
        output: stdout,
        error: stderr,
        env: {
          "ACTRA_EXTENSION_NAME"    => extension.name,
          "ACTRA_EXTENSION_COMMAND" => extension.command,
        }
      )
      raise "extension #{extension.name} failed: #{stderr.to_s.strip}" unless status.success?

      text = stdout.to_s.strip
      return nil if text.empty?
      any = JSON.parse(text)
      any["payload"]? || any
    end

    private def self.discover : Array(ExtensionConfig)
      roots = [
        File.join(Xdg.config_dir, "extensions"),
        File.join(Dir.current, ".actra", "extensions"),
      ]
      out = [] of ExtensionConfig
      roots.each do |root|
        next unless Dir.exists?(root)
        Dir.glob(File.join(root, "*")).sort.each do |path|
          if File.directory?(path)
            index = ["index.sh", "index.cr", "index.js", "index.mjs", "index.ts"].map { |name| File.join(path, name) }.find { |candidate| File.file?(candidate) }
            out << from_source(index) if index
          elsif File.file?(path)
            out << from_source(path)
          end
        end
      end
      out
    end

    private def self.from_source(source : String) : ExtensionConfig
      expanded = source.starts_with?("~") ? source.sub("~", Xdg.home) : source
      name = File.basename(expanded).split(".").first
      command =
        case File.extname(expanded)
        when ".sh"
          "sh #{shell_sq(expanded)}"
        when ".cr"
          "#{crystal_command} run #{shell_sq(File.expand_path("src/actra.cr", Dir.current))} -- __cr-extension #{shell_sq(expanded)}"
        when ".js", ".mjs", ".ts"
          "node #{shell_sq(expanded)}"
        else
          expanded
        end
      ExtensionConfig.new(name, command, [] of String)
    end

    private def self.shell_sq(s : String) : String
      "'" + s.gsub("'", %q('"'"')) + "'"
    end

    private def self.crystal_command : String
      ENV["CRYSTAL"]? || "crystal"
    end
  end
end
