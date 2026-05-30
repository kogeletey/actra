require "json"
require "file_utils"

require "./permission"

module Actra
  struct ToolCall
    getter id : String
    getter name : String
    getter arguments : JSON::Any

    def initialize(@id : String, @name : String, @arguments : JSON::Any)
    end
  end

  struct ToolSpec
    getter name : String
    getter description : String
    getter parameters : JSON::Any
    getter command : String?
    getter builtin : Bool

    def initialize(@name : String, @description : String, @parameters : JSON::Any, @command : String? = nil, @builtin : Bool = false)
    end

    def to_openai_chat : JSON::Any
      JSON.parse(JSON.build do |json|
        json.object do
          json.field "type", "function"
          json.field "function" do
            json.object do
              json.field "name", name
              json.field "description", description
              json.field "parameters", parameters
            end
          end
        end
      end)
    end

    def to_openai_responses : JSON::Any
      JSON.parse(JSON.build do |json|
        json.object do
          json.field "type", "function"
          json.field "name", name
          json.field "description", description
          json.field "parameters", parameters
        end
      end)
    end
  end

  class ToolRegistry
    getter tools : Hash(String, ToolSpec)

    def initialize(@tools : Hash(String, ToolSpec), @permission : PermissionChecker? = nil)
    end

    def self.default(include_builtin : Bool, extension_tools : Array(ToolSpec), allowlist : Array(String)? = nil, permission : PermissionChecker? = nil) : ToolRegistry
      specs = {} of String => ToolSpec
      if include_builtin
        builtin.each { |tool| specs[tool.name] = tool }
      end
      extension_tools.each { |tool| specs[tool.name] = tool }
      if allowlist && !allowlist.empty?
        allowed = allowlist.to_set
        specs = specs.select { |name, _| allowed.includes?(name) }
      end
      new(specs, permission)
    end

    def specs : Array(ToolSpec)
      tools.values
    end

    def execute(call : ToolCall) : String
      tool = tools[call.name]?
      raise "unknown tool: #{call.name}" unless tool
      ensure_permitted(call, tool)
      if tool.builtin
        execute_builtin(tool.name, call.arguments)
      else
        execute_external(tool, call.arguments)
      end
    rescue ex
      "tool #{call.name} failed: #{ex.message}"
    end

    def self.parse_extension_tools(any : JSON::Any) : Array(ToolSpec)
      list = any["tools"]?.try(&.as_a?) || [] of JSON::Any
      list.compact_map do |item|
        name = item["name"]?.try(&.as_s?) || next
        description = item["description"]?.try(&.as_s?) || name
        command = item["command"]?.try(&.as_s?)
        parameters = item["parameters"]? || empty_schema
        ToolSpec.new(name, description, parameters, command, false)
      end
    end

    private def self.builtin : Array(ToolSpec)
      [
        ToolSpec.new("read", "Read a UTF-8 text file from the current workspace.", schema({"path" => "File path to read"}), builtin: true),
        ToolSpec.new("ls", "List files in a directory.", schema({"path" => "Directory path to list"}), builtin: true),
        ToolSpec.new("grep", "Search files with a regular expression using ripgrep.", schema({"pattern" => "Search pattern", "path" => "Optional path"}), builtin: true),
        ToolSpec.new("find", "Find files by shell-style name pattern.", schema({"pattern" => "Filename glob pattern", "path" => "Optional start directory"}), builtin: true),
        ToolSpec.new("bash", "Run a shell command and return stdout and stderr.", schema({"command" => "Shell command to run"}), builtin: true),
        ToolSpec.new("write", "Write text to a file.", schema({"path" => "File path to write", "content" => "File content"}), builtin: true),
        ToolSpec.new("edit", "Replace text in a file.", schema({"path" => "File path to edit", "old" => "Existing text", "new" => "Replacement text"}), builtin: true),
      ]
    end

    private def execute_builtin(name : String, args : JSON::Any) : String
      case name
      when "read"
        File.read(required_arg(args, "path"))
      when "ls"
        path = optional_arg(args, "path") || "."
        Dir.children(path).sort.join("\n")
      when "grep"
        pattern = required_arg(args, "pattern")
        path = optional_arg(args, "path") || "."
        run_capture("rg", [pattern, path])
      when "find"
        pattern = required_arg(args, "pattern")
        path = optional_arg(args, "path") || "."
        run_capture("find", [path, "-name", pattern])
      when "bash"
        command = required_arg(args, "command")
        run_shell(command)
      when "write"
        path = required_arg(args, "path")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, required_arg(args, "content"))
        "wrote #{path}"
      when "edit"
        path = required_arg(args, "path")
        old = required_arg(args, "old")
        new_text = required_arg(args, "new")
        content = File.read(path)
        raise "old text not found in #{path}" unless content.includes?(old)
        File.write(path, content.sub(old, new_text))
        "edited #{path}"
      else
        raise "unsupported builtin tool: #{name}"
      end
    end

    private def ensure_permitted(call : ToolCall, tool : ToolSpec)
      checker = @permission
      return unless checker

      request = permission_request(call, tool)
      decision = checker.check(request)

      case decision
      in PermissionDecision::Allow
        nil
      in PermissionDecision::Ask
        raise "permission required for tool #{call.name}: #{request.input_key}"
      in PermissionDecision::Deny
        raise "permission denied for tool #{call.name}: #{request.input_key}"
      end
    end

    private def permission_request(call : ToolCall, tool : ToolSpec) : PermissionRequest
      arguments = call.arguments
      path = argument_string(arguments, "path") || argument_string(arguments, "file") || argument_string(arguments, "directory")
      command = argument_string(arguments, "command")
      external_command = tool.builtin ? nil : tool.command
      input_key = path || command || "#{call.name}:#{arguments.to_json}"

      PermissionRequest.new(call.name, input_key, path, command || external_command)
    end

    private def argument_string(arguments : JSON::Any, key : String) : String?
      arguments.as_h[key]?.try(&.as_s?)
    rescue
      nil
    end

    private def execute_external(tool : ToolSpec, args : JSON::Any) : String
      command = tool.command || raise "extension tool #{tool.name} has no command"
      output = IO::Memory.new
      error = IO::Memory.new
      input = JSON.build do |json|
        json.object do
          json.field "event", "tool_execute"
          json.field "tool", tool.name
          json.field "payload", args
        end
      end
      status = run_shell_process(command, output, error, IO::Memory.new(input))
      text = output.to_s
      err = error.to_s
      begin
        any = JSON.parse(text)
        if result = any["result"]?.try(&.as_s?)
          text = result
        end
      rescue
      end
      return text unless !status.success? || !err.empty?
      [text, err].reject(&.empty?).join("\n")
    end

    private def required_arg(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || raise "missing argument: #{key}"
    end

    private def optional_arg(args : JSON::Any, key : String) : String?
      args[key]?.try(&.as_s?)
    end

    private def run_shell(command : String) : String
      output = IO::Memory.new
      error = IO::Memory.new
      status = run_shell_process(command, output, error)
      parts = [] of String
      parts << output.to_s unless output.to_s.empty?
      parts << error.to_s unless error.to_s.empty?
      parts << "exit_status=#{status.exit_code}" unless status.success?
      parts.join("\n")
    end

    private def run_capture(command : String, args : Array(String)) : String
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run(command, args, output: output, error: error)
      text = output.to_s
      err = error.to_s
      return text unless !status.success? || !err.empty?
      [text, err].reject(&.empty?).join("\n")
    end

    private def run_shell_process(command : String, output : IO, error : IO, input : IO? = nil) : Process::Status
      if @permission.try(&.sandbox)
        bubblewrap = Process.find_executable("bwrap")
        raise "sandbox requested but bwrap is not installed" unless bubblewrap

        args = [
          "--ro-bind", "/", "/",
          "--bind", Dir.current, Dir.current,
          "--dev", "/dev",
          "--proc", "/proc",
          "--tmpfs", "/tmp",
          "--chdir", Dir.current,
          "/bin/sh", "-c", command,
        ]

        if input
          Process.run(bubblewrap, args, input: input.not_nil!, output: output, error: error)
        else
          Process.run(bubblewrap, args, output: output, error: error)
        end
      elsif input
        Process.run("/bin/sh", ["-c", command], input: input.not_nil!, output: output, error: error)
      else
        Process.run("/bin/sh", ["-c", command], output: output, error: error)
      end
    end

    private def self.schema(properties : Hash(String, String)) : JSON::Any
      JSON.parse(JSON.build do |json|
        json.object do
          json.field "type", "object"
          json.field "properties" do
            json.object do
              properties.each do |name, description|
                json.field name do
                  json.object do
                    json.field "type", "string"
                    json.field "description", description
                  end
                end
              end
            end
          end
          json.field "additionalProperties", false
        end
      end)
    end

    private def self.empty_schema : JSON::Any
      JSON.parse(%({"type":"object","properties":{},"additionalProperties":true}))
    end
  end
end
