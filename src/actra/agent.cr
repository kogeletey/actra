require "json"
require "http/client"

require "./ai_provider"
require "./agent_tool"
require "./context"
require "./extensions"
require "./permission"
require "./session"

module Actra
  struct AgentOptions
    property print_mode : Bool = false
    property io_mode : String = "text"
    property provider : String?
    property model : String?
    property api_key : String?
    property system_prompt : String?
    property append_system_prompt : String?
    property context_files : Bool = true
    property session : String?
    property session_dir : String?
    property save_session : Bool = true
    property continue_session : Bool = false
    property fork_session : String?
    property export_in : String?
    property export_out : String?
    property list_models : String?
    property extensions_enabled : Bool = true
    property explicit_extensions : Array(String) = [] of String
    property tools_enabled : Bool = true
    property builtin_tools_enabled : Bool = true
    property allowed_tools : Array(String)?
    property permission_mode : PermissionMode?
    property sandbox : Bool?
    property prompt_templates : Array(String) = [] of String
    property prompt_modes : Array(String) = [] of String
    property skills : Array(String) = [] of String
    property prompt_args : Array(String) = [] of String
    property list_prompts : Bool = false
    property permission_state : Bool = false
    property permission_allows : Array(PermissionAllowEntry) = [] of PermissionAllowEntry
    property permission_denies : Array(PermissionAllowEntry) = [] of PermissionAllowEntry
    property permission_revokes : Array(PermissionAllowEntry) = [] of PermissionAllowEntry
    property permission_clear : Bool = false

    def permission_mutations? : Bool
      permission_clear || permission_allows.any? || permission_denies.any? || permission_revokes.any?
    end
  end

  module Agent
    def self.run(opts : AgentOptions, stdin : IO, stdout : IO, stderr : IO) : Int32
      cfg = Config.load
      if opts.list_prompts
        PromptPreset.names.each { |name| stdout.puts name }
        return 0
      end
      if search = opts.list_models
        return list_models(cfg, search, stdout)
      end
      if opts.permission_state || opts.permission_mutations?
        session = AgentSession.open(opts.session_dir || cfg.session_dir, opts.session)
        session.append_permission_clear if opts.permission_clear
        opts.permission_allows.each { |entry| session.append_permission_allow(entry.tool, entry.pattern) }
        opts.permission_denies.each { |entry| session.append_permission_deny(entry.tool, entry.pattern) }
        opts.permission_revokes.each { |entry| session.append_permission_revoke(entry.tool, entry.pattern) }
        stdout.puts permission_state(cfg, opts, session).to_json
        return 0
      end
      if export_in = opts.export_in
        path = AgentSession.export_html(opts.session_dir || cfg.session_dir, export_in, opts.export_out)
        stdout.puts "exported: #{path}"
        return 0
      end
      if fork_source = opts.fork_session
        forked = AgentSession.fork(opts.session_dir || cfg.session_dir, fork_source)
        opts.session = forked.id
      elsif opts.continue_session
        recent = AgentSession.recent(opts.session_dir || cfg.session_dir)
        raise "no previous sessions" unless recent
        opts.session = recent.id
      end

      case opts.io_mode
      when "json"
        return run_json(cfg, opts, stdin, stdout, stderr)
      when "rpc"
        return run_rpc(cfg, opts, stdin, stdout, stderr)
      else
        response = complete_once(cfg, opts, stdin, stdout, stderr)
        stdout.puts response.text
      end
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.complete_once(cfg : Config, opts : AgentOptions, stdin : IO, stdout : IO, stderr : IO) : AiResponse
      context = Context.build(opts.prompt_args, stdin, opts.context_files, opts.system_prompt, opts.append_system_prompt, opts.prompt_templates, opts.skills, opts.prompt_modes)
      raise "missing prompt" if context.prompt.empty?

      runtime = ExtensionRuntime.for_config(cfg, opts.explicit_extensions, opts.extensions_enabled)
      extension_resources = opts.extensions_enabled || opts.explicit_extensions.any? ? runtime.emit("resources_discover", JSON.parse(%({"tools":[]}))) : JSON.parse(%({"tools":[]}))
      extension_tools = ToolRegistry.parse_extension_tools(extension_resources)

      session = nil.as(AgentSession?)
      parent_id = nil.as(String?)
      permission_allowlist = [] of PermissionAllowEntry
      permission_denylist = [] of PermissionAllowEntry
      grant_callback = nil.as(Proc(PermissionRequest, Nil)?)
      request_callback = nil.as(Proc(PermissionRequest, Nil)?)
      if opts.save_session
        session = AgentSession.open(opts.session_dir || cfg.session_dir, opts.session)
        active_session = session.not_nil!
        permission_allowlist = active_session.permission_allowlist
        permission_denylist = active_session.permission_denials
        grant_callback = ->(request : PermissionRequest) { active_session.append_permission_allow(request.tool, request.input_key) }
        request_callback = ->(request : PermissionRequest) { active_session.append_permission_request(request) }
      end

      permission = PermissionChecker.new(cfg.permissions, opts.permission_mode, opts.sandbox, permission_allowlist, grant_callback, stdin, stderr, request_callback, permission_denylist)
      registry = ToolRegistry.default(opts.tools_enabled && opts.builtin_tools_enabled, opts.tools_enabled ? extension_tools : [] of ToolSpec, opts.allowed_tools, permission)
      input_payload = JSON.parse(JSON.build do |json|
        json.object do
          json.field "prompt", context.prompt
          json.field "system_prompt", context.system_prompt
          json.field "estimated_prompt_tokens", context.estimated_prompt_tokens
        end
      end)
      input_payload = runtime.emit("input", input_payload)
      prompt = input_payload["prompt"]?.try(&.as_s?) || context.prompt
      system_prompt = input_payload["system_prompt"]?.try(&.as_s?) || context.system_prompt

      if opts.save_session
        parent_id = session.not_nil!.append_message("user", prompt)
      end

      request = AiProvider.build_request(cfg, opts.provider, opts.model, prompt, system_prompt, opts.tools_enabled ? registry.specs : [] of ToolSpec)
      payload = runtime.emit("before_provider_request", request.payload)
      request = AiRequest.new(request.provider, request.model, request.prompt, request.system_prompt, payload, request.tool_specs)
      response = AiProvider.complete(cfg, request, opts.api_key)
      if response.tool_calls.any? && opts.tools_enabled
        response = run_tool_loop(cfg, opts, runtime, registry, request, response)
      end

      runtime.emit("agent_end", JSON.parse(JSON.build do |json|
        json.object do
          json.field "text", response.text
          json.field "provider", request.provider
          json.field "model", request.model
          json.field "estimated_prompt_tokens", context.estimated_prompt_tokens
        end
      end))

      session.try(&.append_message("assistant", response.text, parent_id))
      response
    end

    private def self.run_tool_loop(cfg : Config, opts : AgentOptions, runtime : ExtensionRuntime, registry : ToolRegistry, request : AiRequest, response : AiResponse) : AiResponse
      tool_results = [] of String
      response.tool_calls.each do |call|
        runtime.emit("tool_execution_start", JSON.parse(JSON.build do |json|
          json.object do
            json.field "id", call.id
            json.field "name", call.name
            json.field "arguments", call.arguments
          end
        end))
        result = registry.execute(call)
        runtime.emit("tool_execution_end", JSON.parse(JSON.build do |json|
          json.object do
            json.field "id", call.id
            json.field "name", call.name
            json.field "result", result
          end
        end))
        tool_results << "Tool #{call.name} (#{call.id}) result:\n#{result}"
      end

      follow_up_prompt = String.build do |io|
        io.puts request.prompt
        io.puts
        io.puts "Tool results:"
        io.puts tool_results.join("\n\n")
        io.puts
        io.puts "Use the tool results to answer the original request."
      end
      follow_up = AiProvider.build_request(cfg, opts.provider, opts.model, follow_up_prompt, request.system_prompt, [] of ToolSpec)
      AiProvider.complete(cfg, follow_up, opts.api_key)
    end

    private def self.list_models(cfg : Config, search : String?, stdout : IO) : Int32
      query = search.try(&.downcase)
      cfg.providers.each do |provider_name, provider|
        live_models = provider.models.empty? && live_model_listing_requested?(provider_name, provider, query) ? live_model_names(provider) : [] of String
        if live_models.any?
          live_models.each do |model|
            line = "#{provider_name}/#{model}\t#{provider.api}\t#{provider.base_url}"
            stdout.puts line if !query || line.downcase.includes?(query)
          end
        elsif provider.models.empty?
          model = provider.default_model || cfg.default_model || ENV["ACTRA_MODEL"]? || Config::DEFAULT_MODEL
          line = "#{provider_name}/#{model}\t#{provider.api}\t#{provider.base_url}"
          stdout.puts line if !query || line.downcase.includes?(query)
        else
          provider.models.each_key do |model|
            line = "#{provider_name}/#{model}\t#{provider.api}\t#{provider.base_url}"
            stdout.puts line if !query || line.downcase.includes?(query)
          end
        end
      end
      0
    end

    private def self.live_model_names(provider : AiProviderConfig) : Array(String)
      return [] of String unless {"openai-chat", "openai-completions", "openai-chat-completions"}.includes?(provider.api)
      return [] of String unless local_base_url?(provider.base_url)

      response = HTTP::Client.get("#{provider.base_url}/models")
      return [] of String unless response.status_code >= 200 && response.status_code < 300

      any = JSON.parse(response.body)
      data = any["data"]?.try(&.as_a?) || [] of JSON::Any
      data.compact_map { |item| item["id"]?.try(&.as_s?) }
    rescue
      [] of String
    end

    private def self.live_model_listing_requested?(provider_name : String, provider : AiProviderConfig, query : String?) : Bool
      return false unless query
      return false if query.empty?
      provider_name.downcase.includes?(query) || provider.base_url.downcase.includes?(query)
    end

    private def self.local_base_url?(base_url : String) : Bool
      base_url.starts_with?("http://127.0.0.1:") ||
        base_url.starts_with?("http://localhost:") ||
        base_url.starts_with?("http://[::1]:")
    end

    private def self.run_json(cfg : Config, opts : AgentOptions, stdin : IO, stdout : IO, stderr : IO) : Int32
      session = AgentSession.open(opts.session_dir || cfg.session_dir, opts.session)
      emit(stdout, {"type" => "session", "version" => 3, "id" => session.id, "timestamp" => Time.utc.to_rfc3339, "cwd" => Dir.current, "permissions" => permission_state(cfg, opts, session)})
      emit(stdout, {"type" => "agent_start"})
      emit(stdout, {"type" => "turn_start"})
      json_opts = opts
      json_opts.session = session.id
      response = complete_once(cfg, json_opts, stdin, stdout, stderr)
      emit(stdout, {"type" => "message_start", "role" => "assistant"})
      emit(stdout, {"type" => "message_update", "content" => response.text})
      emit(stdout, {"type" => "message_end"})
      emit(stdout, {"type" => "turn_end"})
      emit(stdout, {"type" => "agent_end"})
      0
    end

    private def self.run_rpc(cfg : Config, opts : AgentOptions, stdin : IO, stdout : IO, stderr : IO) : Int32
      session = AgentSession.open(opts.session_dir || cfg.session_dir, opts.session)
      stdout.puts({"type" => "ready", "session_id" => session.id}.to_json)
      stdout.flush

      stdin.each_line do |line|
        next if line.strip.empty?
        command = JSON.parse(line)
        id = command["id"]?.try(&.as_s?)
        case command["type"]?.try(&.as_s?) || command["command"]?.try(&.as_s?)
        when "prompt"
          prompt = command["prompt"]?.try(&.as_s?) || command["message"]?.try(&.as_s?) || ""
          rpc_opts = opts
          rpc_opts.prompt_args = [prompt]
          rpc_opts.session = session.id
          response = complete_once(cfg, rpc_opts, IO::Memory.new, stdout, stderr)
          stdout.puts({"type" => "response", "id" => id, "command" => "prompt", "success" => true, "text" => response.text, "data" => {"text" => response.text}}.to_json)
        when "get_state"
          stdout.puts({"type" => "response", "id" => id, "command" => "get_state", "success" => true, "data" => {"session_id" => session.id, "cwd" => Dir.current, "permissions" => permission_state(cfg, opts, session)}}.to_json)
        when "get_messages"
          stdout.puts({"type" => "response", "id" => id, "command" => "get_messages", "success" => true, "data" => {"messages" => session.messages}}.to_json)
        when "permissions", "permission_state"
          stdout.puts({"type" => "response", "id" => id, "command" => "permissions", "success" => true, "data" => permission_state(cfg, opts, session)}.to_json)
        when "permission_mode", "set_permission_mode"
          mode = command["mode"]?.try(&.as_s?) || raise "permission_mode requires mode"
          opts.permission_mode = PermissionMode.from(mode)
          stdout.puts({"type" => "response", "id" => id, "command" => "permission_mode", "success" => true, "data" => permission_state(cfg, opts, session)}.to_json)
        when "permission_allow", "allow_permission"
          tool = command["tool"]?.try(&.as_s?) || raise "permission_allow requires tool"
          pattern = command["pattern"]?.try(&.as_s?) || command["input_key"]?.try(&.as_s?) || raise "permission_allow requires pattern"
          session.append_permission_allow(tool, pattern)
          stdout.puts({"type" => "response", "id" => id, "command" => "permission_allow", "success" => true, "data" => permission_state(cfg, opts, session)}.to_json)
        when "permission_revoke", "revoke_permission"
          tool = command["tool"]?.try(&.as_s?) || raise "permission_revoke requires tool"
          pattern = command["pattern"]?.try(&.as_s?) || command["input_key"]?.try(&.as_s?) || raise "permission_revoke requires pattern"
          session.append_permission_revoke(tool, pattern)
          stdout.puts({"type" => "response", "id" => id, "command" => "permission_revoke", "success" => true, "data" => permission_state(cfg, opts, session)}.to_json)
        when "permission_deny", "permission_dismiss", "deny_permission", "dismiss_permission"
          tool = command["tool"]?.try(&.as_s?) || raise "permission_deny requires tool"
          pattern = command["pattern"]?.try(&.as_s?) || command["input_key"]?.try(&.as_s?) || raise "permission_deny requires pattern"
          session.append_permission_deny(tool, pattern)
          stdout.puts({"type" => "response", "id" => id, "command" => "permission_deny", "success" => true, "data" => permission_state(cfg, opts, session)}.to_json)
        when "permission_clear", "clear_permissions"
          session.append_permission_clear
          stdout.puts({"type" => "response", "id" => id, "command" => "permission_clear", "success" => true, "data" => permission_state(cfg, opts, session)}.to_json)
        when "new_session"
          session = AgentSession.open(opts.session_dir || cfg.session_dir)
          stdout.puts({"type" => "response", "id" => id, "command" => "new_session", "success" => true, "data" => {"session_id" => session.id}}.to_json)
        when "set_model"
          opts.model = command["model"]?.try(&.as_s?)
          stdout.puts({"type" => "response", "id" => id, "command" => "set_model", "success" => true, "data" => {"model" => opts.model}}.to_json)
        when "abort"
          stdout.puts({"type" => "response", "id" => id, "command" => "abort", "success" => true}.to_json)
        else
          stdout.puts({"type" => "response", "id" => id, "success" => false, "error" => "unknown command"}.to_json)
        end
        stdout.flush
      end
      0
    end

    private def self.emit(stdout : IO, fields : Hash) : Nil
      stdout.puts(fields.to_json)
      stdout.flush
    end

    private def self.permission_state(cfg : Config, opts : AgentOptions, session : AgentSession) : Hash(String, JSON::Any)
      effective_mode = opts.permission_mode || cfg.permissions.mode
      effective_sandbox = opts.sandbox.nil? ? cfg.permissions.sandbox : opts.sandbox.not_nil!

      JSON.parse(JSON.build do |json|
        json.object do
          json.field "session_id", session.id
          json.field "session_path", session.path
          json.field "mode", effective_mode.config_value
          json.field "mode_source", opts.permission_mode ? "override" : "config"
          json.field "sandbox", effective_sandbox
          json.field "sandbox_source", opts.sandbox.nil? ? "config" : "override"
          json.field "doom_loop_threshold", cfg.permissions.doom_loop_threshold
          json.field "rules" do
            json.array do
              cfg.permissions.tools.each do |rule|
                json.object do
                  json.field "tool", rule.tool
                  json.field "allow", rule.allow
                  json.field "ask", rule.ask
                  json.field "deny", rule.deny
                end
              end
            end
          end
          json.field "allowlist" do
            json.array do
              session.permission_allowlist.each do |entry|
                json.object do
                  json.field "tool", entry.tool
                  json.field "pattern", entry.pattern
                end
              end
            end
          end
          json.field "denials" do
            json.array do
              session.permission_denials.each do |entry|
                json.object do
                  json.field "tool", entry.tool
                  json.field "pattern", entry.pattern
                end
              end
            end
          end
          json.field "decisions" do
            json.array do
              session.permission_decisions.each do |pair|
                decision = pair[0]
                entry = pair[1]
                json.object do
                  json.field "decision", decision
                  json.field "tool", entry.tool
                  json.field "pattern", entry.pattern
                end
              end
            end
          end
          json.field "requests" do
            json.array do
              session.pending_permission_requests.each do |request|
                json.object do
                  json.field "tool", request.tool
                  json.field "input_key", request.input_key
                  json.field "path", request.path if request.path
                  json.field "command", request.command if request.command
                  json.field "reason", request.reason if request.reason
                  json.field "count", request.count if request.count
                end
              end
            end
          end
        end
      end).as_h
    end
  end
end
