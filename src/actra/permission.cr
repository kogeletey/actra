module Actra
  enum PermissionMode
    Standard
    Restrictive
    AcceptAll
    Yolo

    def config_value : String
      case self
      when PermissionMode::Standard
        "standard"
      when PermissionMode::Restrictive
        "restrictive"
      when PermissionMode::AcceptAll
        "accept-all"
      when PermissionMode::Yolo
        "yolo"
      else
        "standard"
      end
    end

    def self.from(value : String?) : PermissionMode
      normalized = value ? value.strip.downcase : nil

      case normalized
      when nil, "", "standard"
        Standard
      when "restrictive", "restricted"
        Restrictive
      when "accept", "accept-all", "accept_all", "acceptall"
        AcceptAll
      when "yolo"
        Yolo
      else
        raise ArgumentError.new("unknown permission mode: #{value}")
      end
    end
  end

  struct ToolPermissionConfig
    getter tool : String
    getter allow : Array(String)
    getter ask : Array(String)
    getter deny : Array(String)

    def initialize(
      @tool : String,
      @allow : Array(String) = [] of String,
      @ask : Array(String) = [] of String,
      @deny : Array(String) = [] of String
    )
    end
  end

  struct PermissionsConfig
    getter mode : PermissionMode
    getter sandbox : Bool
    getter tools : Array(ToolPermissionConfig)
    getter doom_loop_threshold : Int32

    def initialize(
      @mode : PermissionMode = PermissionMode::Standard,
      @sandbox : Bool = false,
      @tools : Array(ToolPermissionConfig) = [] of ToolPermissionConfig,
      @doom_loop_threshold : Int32 = 8
    )
    end

    def self.default : PermissionsConfig
      new
    end

    def tool_config(name : String) : ToolPermissionConfig?
      @tools.find { |tool| tool.tool == name }
    end
  end

  struct PermissionAllowEntry
    getter tool : String
    getter pattern : String

    def initialize(@tool : String, @pattern : String)
    end

    def matches?(request : PermissionRequest) : Bool
      return false unless tool == request.tool
      return true if matches_pattern?(pattern, request.input_key)
      return true if request.path && matches_pattern?(pattern, request.path.not_nil!)
      return true if request.command && matches_pattern?(pattern, request.command.not_nil!)
      false
    end

    private def matches_pattern?(pattern : String, value : String) : Bool
      normalized = pattern.strip
      return false if normalized.empty?
      return true if normalized == "*" || normalized == "**"
      return true if normalized == value

      File.match?(normalized, value)
    rescue
      false
    end
  end

  enum PermissionDecision
    Allow
    Ask
    Deny
  end

  struct PermissionRequest
    getter tool : String
    getter input_key : String
    getter path : String?
    getter command : String?
    getter reason : String?
    getter count : Int32?

    def initialize(
      @tool : String,
      @input_key : String,
      @path : String? = nil,
      @command : String? = nil,
      @reason : String? = nil,
      @count : Int32? = nil
    )
    end

    def with_context(reason : String, count : Int32? = nil) : PermissionRequest
      PermissionRequest.new(tool, input_key, path, command, reason, count)
    end
  end

  class PermissionChecker
    READ_TOOLS  = ["read", "ls", "grep", "find"]
    WRITE_TOOLS = ["write", "edit"]
    SHELL_TOOLS = ["bash", "shell", "sh"]

    getter mode : PermissionMode
    getter sandbox : Bool

    @mode : PermissionMode
    @sandbox : Bool
    @seen : Hash(String, Int32)

    def initialize(
      @config : PermissionsConfig = PermissionsConfig.default,
      mode_override : PermissionMode? = nil,
      sandbox_override : Bool? = nil,
      @session_allowlist : Array(PermissionAllowEntry) = [] of PermissionAllowEntry,
      @grant_callback : Proc(PermissionRequest, Nil)? = nil,
      @ask_input : IO = STDIN,
      @ask_output : IO = STDERR,
      @request_callback : Proc(PermissionRequest, Nil)? = nil,
      @session_denylist : Array(PermissionAllowEntry) = [] of PermissionAllowEntry
    )
      @mode = mode_override || @config.mode
      @sandbox = sandbox_override.nil? ? @config.sandbox : sandbox_override.not_nil!
      @seen = Hash(String, Int32).new(0)
    end

    def check(request : PermissionRequest) : PermissionDecision
      key = "#{request.tool}:#{request.input_key}"
      @seen[key] += 1

      return PermissionDecision::Allow if @mode == PermissionMode::Yolo

      explicit = explicit_decision(request)
      return PermissionDecision::Deny if explicit == PermissionDecision::Deny

      return PermissionDecision::Deny if session_denied?(request)

      if @seen[key] > @config.doom_loop_threshold
        return resolve_ask(request.with_context("doom-loop", @seen[key]), PermissionDecision::Ask)
      end

      return explicit if explicit
      return PermissionDecision::Allow if session_allowed?(request)

      case @mode
      in PermissionMode::AcceptAll
        PermissionDecision::Allow
      in PermissionMode::Standard
        resolve_ask(request.with_context("policy", @seen[key]), standard_decision(request))
      in PermissionMode::Restrictive
        resolve_ask(request.with_context("policy", @seen[key]), PermissionDecision::Ask)
      in PermissionMode::Yolo
        PermissionDecision::Allow
      end
    end

    private def explicit_decision(request : PermissionRequest) : PermissionDecision?
      tool = @config.tool_config(request.tool)
      return nil unless tool

      return PermissionDecision::Deny if matches_any?(tool.deny, request)
      return PermissionDecision::Ask if matches_any?(tool.ask, request)
      return PermissionDecision::Allow if matches_any?(tool.allow, request)

      nil
    end

    private def session_allowed?(request : PermissionRequest) : Bool
      @session_allowlist.any? do |entry|
        entry.matches?(request)
      end
    end

    private def session_denied?(request : PermissionRequest) : Bool
      @session_denylist.any? do |entry|
        entry.matches?(request)
      end
    end

    private def standard_decision(request : PermissionRequest) : PermissionDecision
      return PermissionDecision::Ask if WRITE_TOOLS.includes?(request.tool)
      return PermissionDecision::Ask if SHELL_TOOLS.includes?(request.tool)

      if READ_TOOLS.includes?(request.tool)
        path = request.path || "."
        return path_inside_cwd?(path) ? PermissionDecision::Allow : PermissionDecision::Ask
      end

      PermissionDecision::Ask
    end

    private def resolve_ask(request : PermissionRequest, decision : PermissionDecision) : PermissionDecision
      return decision unless decision == PermissionDecision::Ask
      unless @ask_input.tty? && @ask_output.tty?
        if callback = @request_callback
          callback.call(request)
        end
        return decision
      end

      @ask_output.print "actra permission request: allow #{request.tool} #{request.input_key}? [y/N] "
      answer = @ask_input.gets.try(&.strip.downcase)
      case answer
      when "y", "yes", "allow"
        if callback = @grant_callback
          callback.call(request)
        end
        PermissionDecision::Allow
      else
        if callback = @request_callback
          callback.call(request)
        end
        PermissionDecision::Ask
      end
    rescue
      PermissionDecision::Ask
    end

    private def matches_any?(patterns : Array(String), request : PermissionRequest) : Bool
      patterns.any? do |pattern|
        next true if matches?(pattern, request.input_key)
        next true if request.path && matches?(pattern, request.path.not_nil!)
        next true if request.command && matches?(pattern, request.command.not_nil!)
        false
      end
    end

    private def matches?(pattern : String, value : String) : Bool
      normalized = pattern.strip
      return false if normalized.empty?
      return true if normalized == "*" || normalized == "**"
      return true if normalized == value

      File.match?(normalized, value)
    rescue
      false
    end

    private def path_inside_cwd?(path : String) : Bool
      expanded = File.expand_path(path)
      cwd = File.expand_path(Dir.current)

      expanded == cwd || expanded.starts_with?(cwd + "/")
    rescue
      false
    end
  end
end
