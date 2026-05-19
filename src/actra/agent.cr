require "json"

require "./ai_provider"
require "./agent_tool"
require "./context"
require "./extensions"
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
    property prompt_templates : Array(String) = [] of String
    property skills : Array(String) = [] of String
    property prompt_args : Array(String) = [] of String
  end

  module Agent
    def self.run(opts : AgentOptions, stdin : IO, stdout : IO, stderr : IO) : Int32
      cfg = Config.load
      if search = opts.list_models
        return list_models(cfg, search, stdout)
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
        return run_json(cfg, opts, stdin, stdout)
      when "rpc"
        return run_rpc(cfg, opts, stdin, stdout)
      else
        response = complete_once(cfg, opts, stdin, stdout)
        stdout.puts response.text
      end
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.complete_once(cfg : Config, opts : AgentOptions, stdin : IO, stdout : IO) : AiResponse
      context = Context.build(opts.prompt_args, stdin, opts.context_files, opts.system_prompt, opts.append_system_prompt, opts.prompt_templates, opts.skills)
      raise "missing prompt" if context.prompt.empty?

      runtime = ExtensionRuntime.for_config(cfg, opts.explicit_extensions, opts.extensions_enabled)
      extension_resources = opts.extensions_enabled || opts.explicit_extensions.any? ? runtime.emit("resources_discover", JSON.parse(%({"tools":[]}))) : JSON.parse(%({"tools":[]}))
      extension_tools = ToolRegistry.parse_extension_tools(extension_resources)
      registry = ToolRegistry.default(opts.tools_enabled && opts.builtin_tools_enabled, opts.tools_enabled ? extension_tools : [] of ToolSpec, opts.allowed_tools)
      input_payload = JSON.parse(JSON.build do |json|
        json.object do
          json.field "prompt", context.prompt
          json.field "system_prompt", context.system_prompt
        end
      end)
      input_payload = runtime.emit("input", input_payload)
      prompt = input_payload["prompt"]?.try(&.as_s?) || context.prompt
      system_prompt = input_payload["system_prompt"]?.try(&.as_s?) || context.system_prompt

      session = nil.as(AgentSession?)
      parent_id = nil.as(String?)
      if opts.save_session
        session = AgentSession.open(opts.session_dir || cfg.session_dir, opts.session)
        parent_id = session.append_message("user", prompt)
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
        if provider.models.empty?
          model = provider.default_model || cfg.default_model || ENV["ACTRA_MODEL"]? || "gpt-4.1-mini"
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

    private def self.run_json(cfg : Config, opts : AgentOptions, stdin : IO, stdout : IO) : Int32
      session = AgentSession.open(opts.session_dir || cfg.session_dir, opts.session)
      emit(stdout, {"type" => "session", "version" => 3, "id" => session.id, "timestamp" => Time.utc.to_rfc3339, "cwd" => Dir.current})
      emit(stdout, {"type" => "agent_start"})
      emit(stdout, {"type" => "turn_start"})
      json_opts = opts
      json_opts.session = session.id
      response = complete_once(cfg, json_opts, stdin, stdout)
      emit(stdout, {"type" => "message_start", "role" => "assistant"})
      emit(stdout, {"type" => "message_update", "content" => response.text})
      emit(stdout, {"type" => "message_end"})
      emit(stdout, {"type" => "turn_end"})
      emit(stdout, {"type" => "agent_end"})
      0
    end

    private def self.run_rpc(cfg : Config, opts : AgentOptions, stdin : IO, stdout : IO) : Int32
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
          response = complete_once(cfg, rpc_opts, IO::Memory.new, stdout)
          stdout.puts({"type" => "response", "id" => id, "command" => "prompt", "success" => true, "text" => response.text, "data" => {"text" => response.text}}.to_json)
        when "get_state"
          stdout.puts({"type" => "response", "id" => id, "command" => "get_state", "success" => true, "data" => {"session_id" => session.id, "cwd" => Dir.current}}.to_json)
        when "get_messages"
          stdout.puts({"type" => "response", "id" => id, "command" => "get_messages", "success" => true, "data" => {"messages" => session.messages}}.to_json)
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
  end
end
