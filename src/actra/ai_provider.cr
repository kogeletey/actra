require "http/client"
require "json"
require "uri"

require "./config"
require "./request"
require "./agent_tool"
require "./forgefed"

module Actra
  struct AiRequest
    getter provider : String
    getter model : String
    getter prompt : String
    getter system_prompt : String?
    getter payload : JSON::Any
    getter tool_specs : Array(ToolSpec)

    def initialize(@provider : String, @model : String, @prompt : String, @system_prompt : String?, @payload : JSON::Any, @tool_specs : Array(ToolSpec) = [] of ToolSpec)
    end
  end

  struct AiResponse
    getter text : String
    getter raw : JSON::Any
    getter tool_calls : Array(ToolCall)

    def initialize(@text : String, @raw : JSON::Any, @tool_calls : Array(ToolCall) = [] of ToolCall)
    end
  end

  class AiProvider
    def self.build_request(cfg : Config, provider_name : String?, model_name : String?, prompt : String, system_prompt : String?, tools : Array(ToolSpec) = [] of ToolSpec) : AiRequest
      provider = cfg.provider(provider_name)
      raise "unknown provider: #{provider_name || cfg.default_provider}" unless provider

      model = model_name || cfg.default_model || provider.default_model || ENV["ACTRA_MODEL"]? || (provider.api == "forgefed" ? "ticket" : Config::DEFAULT_MODEL)
      payload = payload_for(provider, model, prompt, system_prompt, tools)
      AiRequest.new(provider.name, model, prompt, system_prompt, payload, tools)
    end

    def self.complete(cfg : Config, request : AiRequest, api_key_override : String? = nil) : AiResponse
      provider = cfg.provider(request.provider)
      raise "unknown provider: #{request.provider}" unless provider
      return complete_forgefed(cfg, provider, request) if provider.api == "forgefed"

      url =
        case provider.api
        when "openai-responses"
          join_url(provider.base_url, "/responses")
        when "openai-completions", "openai-chat-completions", "openai-chat"
          join_url(provider.base_url, "/chat/completions")
        else
          raise "unsupported provider api: #{provider.api}"
        end

      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      provider.headers.each { |k, v| headers[k] = resolve_secret(v) }
      if provider.auth_header
        key_source = api_key_override || provider.api_key
        if key_source
          api_key = resolve_secret(key_source)
          headers["Authorization"] = "Bearer #{api_key}" unless api_key.empty?
        end
      end

      HTTP::Client.post(url, headers: headers, body: request.payload.to_json) do |resp|
        body = resp.body_io.gets_to_end
        unless resp.status_code >= 200 && resp.status_code < 300
          raise "provider http #{resp.status_code}: #{body}"
        end
        raw = JSON.parse(body)
        AiResponse.new(extract_text(provider.api, raw), raw, extract_tool_calls(provider.api, raw))
      end
    end

    private def self.complete_forgefed(cfg : Config, provider : AiProviderConfig, request : AiRequest) : AiResponse
      server = cfg.server(provider.forgefed_server) || raise "unknown ForgeFed server for provider #{provider.name}: #{provider.forgefed_server || cfg.default_server}"
      actor_ref = provider.forgefed_actor || provider.name
      actor = server.actor_for_command(actor_ref) || server.actors.find { |candidate| candidate.name == actor_ref }
      raise "unknown ForgeFed actor for provider #{provider.name}: #{actor_ref}" unless actor

      delivery = ForgeFed.build_ticket_activity(server, actor, actor.name, request.prompt, sign: true)
      response = ForgeFed.post(delivery)
      body = response.body
      unless response.status_code >= 200 && response.status_code < 300
        raise "forgefed provider http #{response.status_code}: #{body}"
      end

      text = body.empty? ? "forgefed ticket delivered to #{actor.name}" : body
      raw = JSON.parse(JSON.build do |json|
        json.object do
          json.field "provider", provider.name
          json.field "server", server.name
          json.field "actor", actor.name
          json.field "status", response.status_code
          json.field "url", delivery.url
          json.field "body", body
        end
      end)
      AiResponse.new(text, raw)
    end

    private def self.payload_for(provider : AiProviderConfig, model : String, prompt : String, system_prompt : String?, tools : Array(ToolSpec)) : JSON::Any
      case provider.api
      when "openai-responses"
        JSON.parse(JSON.build do |json|
          json.object do
            json.field "model", model
            json.field "input", prompt
            json.field "instructions", system_prompt if system_prompt && !system_prompt.empty?
            if tools.any?
              json.field "tools" do
                json.array do
                  tools.each { |tool| json.raw tool.to_openai_responses.to_json }
                end
              end
            end
          end
        end)
      when "forgefed"
        JSON.parse(JSON.build do |json|
          json.object do
            json.field "model", model
            json.field "input", prompt
            json.field "instructions", system_prompt if system_prompt && !system_prompt.empty?
          end
        end)
      when "openai-completions", "openai-chat-completions", "openai-chat"
        JSON.parse(JSON.build do |json|
          json.object do
            json.field "model", model
            json.field "messages" do
              json.array do
                if system_prompt && !system_prompt.empty?
                  json.object do
                    json.field "role", "system"
                    json.field "content", system_prompt
                  end
                end
                json.object do
                  json.field "role", "user"
                  json.field "content", prompt
                end
              end
            end
            if tools.any?
              json.field "tools" do
                json.array do
                  tools.each { |tool| json.raw tool.to_openai_chat.to_json }
                end
              end
              json.field "tool_choice", "auto"
            end
          end
        end)
      else
        raise "unsupported provider api: #{provider.api}"
      end
    end

    private def self.extract_text(api : String, raw : JSON::Any) : String
      if api == "openai-responses"
        if text = raw["output_text"]?.try(&.as_s?)
          return text
        end
        if output = raw["output"]?.try(&.as_a?)
          parts = [] of String
          output.each do |item|
            next unless content = item["content"]?.try(&.as_a?)
            content.each do |part|
              if part["type"]?.try(&.as_s?) == "output_text"
                if text = part["text"]?.try(&.as_s?)
                  parts << text
                end
              end
            end
          end
          return parts.join
        end
      else
        if choices = raw["choices"]?.try(&.as_a?)
          if first = choices.first?
            if text = first["message"]?.try(&.["content"]?).try(&.as_s?)
              return text
            end
          end
        end
      end

      raw.to_json
    end

    private def self.extract_tool_calls(api : String, raw : JSON::Any) : Array(ToolCall)
      calls = [] of ToolCall
      if api == "openai-responses"
        if output = raw["output"]?.try(&.as_a?)
          output.each do |item|
            type = item["type"]?.try(&.as_s?)
            next unless type == "function_call" || type == "custom_tool_call"
            name = item["name"]?.try(&.as_s?) || next
            id = item["call_id"]?.try(&.as_s?) || item["id"]?.try(&.as_s?) || name
            raw_args = item["arguments"]?.try(&.as_s?) || item["input"]?.try(&.to_json) || "{}"
            calls << ToolCall.new(id, name, parse_args(raw_args))
          end
        end
      else
        if choices = raw["choices"]?.try(&.as_a?)
          choices.each do |choice|
            next unless tool_calls = choice["message"]?.try(&.["tool_calls"]?).try(&.as_a?)
            tool_calls.each do |tool_call|
              function = tool_call["function"]?
              next unless function
              name = function["name"]?.try(&.as_s?) || next
              id = tool_call["id"]?.try(&.as_s?) || name
              raw_args = function["arguments"]?.try(&.as_s?) || "{}"
              calls << ToolCall.new(id, name, parse_args(raw_args))
            end
          end
        end
      end
      calls
    end

    private def self.parse_args(raw : String) : JSON::Any
      JSON.parse(raw.empty? ? "{}" : raw)
    rescue
      JSON.parse(%({"value":#{raw.to_json}}))
    end

    private def self.resolve_secret(value : String) : String
      if value.starts_with?("!")
        command = value[1..].strip
        io = IO::Memory.new
        ok = Process.run("/bin/sh", ["-c", command], output: io, error: Process::Redirect::Inherit)
        raise "secret command failed: #{command}" unless ok.success?
        return io.to_s.strip
      end

      ENV[value]? || value
    end

    private def self.join_url(base : String, path : String) : String
      b = base.ends_with?("/") ? base[0, base.size - 1] : base
      p = path.starts_with?("/") ? path : "/#{path}"
      "#{b}#{p}"
    end
  end
end
