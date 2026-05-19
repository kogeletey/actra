require "json"

module Actra
  module Extension
    alias EventHandler = Proc(JSON::Any, JSON::Any?)
    alias ToolHandler = Proc(JSON::Any, String)
    alias CommandHandler = Proc(String, String)

    class API
      def initialize
        @handlers = {} of String => EventHandler
        @tool_handlers = {} of String => ToolHandler
        @command_handlers = {} of String => CommandHandler
        @tools = [] of JSON::Any
        @commands = [] of JSON::Any
        @providers = [] of JSON::Any
      end

      def on(event : String, &block : JSON::Any -> JSON::Any?)
        @handlers[event] = block
      end

      def register_tool(name : String, description : String, parameters : JSON::Any? = nil, command : String? = nil)
        @tools << tool_json(name, description, parameters, command)
      end

      def register_tool(name : String, description : String, parameters : JSON::Any? = nil, command : String? = nil, &block : JSON::Any -> String)
        @tool_handlers[name] = block
        @tools << tool_json(name, description, parameters, command || ENV["ACTRA_EXTENSION_COMMAND"]?)
      end

      def register_command(name : String, description : String = "", &block : String -> String)
        @command_handlers[name] = block
        @commands << JSON.parse({"name" => name, "description" => description}.to_json)
      end

      def register_command(name : String, description : String = "", command : String? = nil)
        obj = {"name" => name, "description" => description}
        obj["command"] = command if command
        @commands << JSON.parse(obj.to_json)
      end

      def register_provider(name : String, config : JSON::Any)
        @providers << JSON.parse(JSON.build do |json|
          json.object do
            json.field "name", name
            json.field "config", config
          end
        end)
      end

      def dispatch(event : String, envelope : JSON::Any) : JSON::Any?
        case event
        when "resources_discover"
          payload = envelope["payload"]? || JSON.parse(%({"tools":[],"commands":[],"providers":[]}))
          return merge_resources(payload)
        when "tool_execute"
          tool_name = envelope["tool"]?.try(&.as_s?) || envelope["payload"]?.try(&.["tool"]?).try(&.as_s?)
          args = envelope["payload"]? || JSON.parse("{}")
          if tool_name && (handler = @tool_handlers[tool_name]?)
            return JSON.parse({"result" => handler.call(args)}.to_json)
          end
          return nil
        when "command_execute"
          command_name = envelope["command"]?.try(&.as_s?) || envelope["payload"]?.try(&.["command"]?).try(&.as_s?)
          args = envelope["args"]?.try(&.as_s?) || envelope["payload"]?.try(&.["args"]?).try(&.as_s?) || ""
          if command_name && (handler = @command_handlers[command_name]?)
            return JSON.parse({"result" => handler.call(args)}.to_json)
          end
          return nil
        else
          if handler = @handlers[event]?
            return handler.call(envelope["payload"]? || JSON.parse("{}"))
          end
        end
        nil
      end

      private def merge_resources(payload : JSON::Any) : JSON::Any
        JSON.parse(JSON.build do |json|
          json.object do
            json.field "tools" do
              json.array do
                append_array(json, payload["tools"]?)
                @tools.each { |tool| json.raw tool.to_json }
              end
            end
            json.field "commands" do
              json.array do
                append_array(json, payload["commands"]?)
                @commands.each { |command| json.raw command.to_json }
              end
            end
            json.field "providers" do
              json.array do
                append_array(json, payload["providers"]?)
                @providers.each { |provider| json.raw provider.to_json }
              end
            end
          end
        end)
      end

      private def append_array(json : JSON::Builder, value : JSON::Any?) : Nil
        return unless value
        value.as_a?.try do |items|
          items.each { |item| json.raw item.to_json }
        end
      end

      private def tool_json(name : String, description : String, parameters : JSON::Any?, command : String?) : JSON::Any
        JSON.parse(JSON.build do |json|
          json.object do
            json.field "name", name
            json.field "description", description
            json.field "parameters", parameters || empty_schema
            json.field "command", command if command
          end
        end)
      end

      private def empty_schema : JSON::Any
        JSON.parse(%({"type":"object","properties":{},"additionalProperties":true}))
      end
    end

    def self.run(&block : API ->)
      input = STDIN.gets_to_end.strip
      envelope = input.empty? ? JSON.parse(%({"event":"resources_discover","payload":{}})) : JSON.parse(input)
      event = envelope["event"]?.try(&.as_s?) || "resources_discover"
      api = API.new
      yield api
      result = api.dispatch(event, envelope)
      STDOUT.puts(result.to_json) if result
    end
  end
end
