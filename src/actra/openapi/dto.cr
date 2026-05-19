require "json"

require "./document"
require "./ref_resolver"

module Actra::OpenAPI
  module Dto
    class Schema
      getter type : String?
      getter format : String?
      getter description : String?
      getter enum_values : Array(String)
      getter properties : Hash(String, Schema)
      getter required : Array(String)
      getter items : Schema?
      getter ref : String?

      def initialize(
        @type : String?,
        @format : String?,
        @description : String?,
        @enum_values : Array(String),
        @properties : Hash(String, Schema),
        @required : Array(String),
        @items : Schema?,
        @ref : String?
      )
      end

      def self.empty : Schema
        Schema.new(nil, nil, nil, [] of String, {} of String => Schema, [] of String, nil, nil)
      end

      def objectish? : Bool
        (@type == "object") || @properties.size > 0
      end

      def arrayish? : Bool
        (@type == "array") || !@items.nil?
      end
    end

    struct Parameter
      getter name : String
      getter location : String # "path" | "query" | "header"
      getter required : Bool
      getter description : String?
      getter schema : Schema?

      def initialize(@name : String, @location : String, @required : Bool, @description : String?, @schema : Schema?)
      end
    end

    struct RequestBody
      getter required : Bool
      getter content_type : String
      getter schema : Schema

      def initialize(@required : Bool, @content_type : String, @schema : Schema)
      end
    end

    struct Operation
      getter method : String
      getter path_template : String
      getter summary : String?
      getter description : String?
      getter operation_id : String?
      getter parameters : Array(Parameter)
      getter request_body_json : RequestBody?

      def initialize(
        @method : String,
        @path_template : String,
        @summary : String?,
        @description : String?,
        @operation_id : String?,
        @parameters : Array(Parameter),
        @request_body_json : RequestBody?
      )
      end
    end

    struct OperationListItem
      getter method : String
      getter path_template : String
      getter summary : String?

      def initialize(@method : String, @path_template : String, @summary : String?)
      end
    end

    class Builder
      HTTP_METHODS = ["get", "post", "put", "patch", "delete", "head", "options"]
      PARAM_LOCS   = ["path", "query", "header"]

      def initialize(@doc : Document)
        @resolver = RefResolver.new(@doc)
      end

      def list_operations : Array(OperationListItem)
        out = [] of OperationListItem

        paths_any = @doc.raw["paths"]?
        if !paths_any.nil?
          paths = paths_any.not_nil!.as_h?
          if !paths.nil?
            paths_h = paths.not_nil!
            paths_h.each do |path, item_any|
              item = item_any.as_h?
              if item.nil?
                next
              end

              item_h = item.not_nil!
              item_h.each do |k, v|
                if k == "parameters"
                  next
                end
                m = k.downcase
                unless HTTP_METHODS.includes?(m)
                  next
                end
                op_h = v.as_h?
                if op_h.nil?
                  next
                end

                summary = op_h.not_nil!["summary"]?.try(&.as_s?)
                if summary.nil?
                  if d = op_h.not_nil!["description"]?.try(&.as_s?)
                    summary = first_line(d)
                  end
                end

                out << OperationListItem.new(m, path, summary)
              end
            end
          end
        end

        out
      end

      def operation(method : String, path_template : String) : Operation
        paths_any = @doc.raw["paths"]?
        if paths_any.nil?
          raise "missing paths"
        end
        paths = paths_any.not_nil!.as_h?
        if paths.nil?
          raise "missing paths"
        end

        path_item_any = paths.not_nil![path_template]?
        if path_item_any.nil?
          raise "missing path template: #{path_template}"
        end
        path_item = path_item_any.not_nil!.as_h?
        if path_item.nil?
          raise "invalid path item: #{path_template}"
        end

        op_any = path_item.not_nil![method.downcase]?
        if op_any.nil?
          raise "missing operation: #{method.upcase} #{path_template}"
        end
        op_h = op_any.not_nil!.as_h?
        if op_h.nil?
          raise "invalid operation: #{method.upcase} #{path_template}"
        end

        summary = op_h.not_nil!["summary"]?.try(&.as_s?)
        description = op_h.not_nil!["description"]?.try(&.as_s?)
        operation_id = op_h.not_nil!["operationId"]?.try(&.as_s?)

        params = parse_parameters(path_item.not_nil!["parameters"]?, op_h.not_nil!["parameters"]?)
        request_body = parse_request_body(op_h.not_nil!)

        Operation.new(method.downcase, path_template, summary, description, operation_id, params, request_body)
      end

      private def schema_from_any(any : JSON::Any) : Schema
        h = any.as_h?
        return Schema.empty if h.nil?
        h = h.not_nil!

        if ref = h["$ref"]?.try(&.as_s?)
          begin
            resolved = @resolver.resolve_schema_any(any)
            s = schema_from_any(resolved)
            return Schema.new(s.type, s.format, s.description, s.enum_values, s.properties, s.required, s.items, ref)
          rescue
            return Schema.new(nil, nil, nil, [] of String, {} of String => Schema, [] of String, nil, ref)
          end
        end

        desc = h["description"]?.try(&.as_s?)
        t = h["type"]?.try(&.as_s?)
        fmt = h["format"]?.try(&.as_s?)

        enum_values = [] of String
        if ev = h["enum"]?.try(&.as_a?)
          ev.each do |v|
            if s = v.as_s?
              enum_values << s
            end
          end
        end

        required = [] of String
        if ra = h["required"]?.try(&.as_a?)
          ra.each do |v|
            if s = v.as_s?
              required << s
            end
          end
        end
        required = required.uniq

        properties = {} of String => Schema
        if ph = h["properties"]?.try(&.as_h?)
          ph.each do |name, p_any|
            properties[name] = schema_from_any(p_any)
          end
          if t.nil?
            t = "object"
          end
        end

        items = nil.as(Schema?)
        if it_any = h["items"]?
          items = schema_from_any(it_any)
          if t.nil?
            t = "array"
          end
        end

        Schema.new(t, fmt, desc, enum_values, properties, required, items, nil)
      end

      private def parse_parameters(path_params_any : JSON::Any?, op_params_any : JSON::Any?) : Array(Parameter)
        raw = [] of JSON::Any
        if a = path_params_any.try(&.as_a?)
          raw.concat(a)
        end
        if a = op_params_any.try(&.as_a?)
          raw.concat(a)
        end

        out = [] of Parameter
        seen = {} of String => Bool

        raw.each do |p_any|
          ph = p_any.as_h?
          if ph.nil?
            next
          end

          name = ph.not_nil!["name"]?.try(&.as_s?)
          loc = ph.not_nil!["in"]?.try(&.as_s?)
          if name.nil? || loc.nil?
            next
          end
          unless PARAM_LOCS.includes?(loc.not_nil!)
            next
          end

          key = "#{loc}:#{name}"
          if seen[key]?
            next
          end
          seen[key] = true

          desc = ph.not_nil!["description"]?.try(&.as_s?)
          required = ph.not_nil!["required"]?.try(&.as_bool?) || false
          if loc == "path"
            required = true
          end

          schema = nil.as(Schema?)
          if sh = ph.not_nil!["schema"]?
            schema = schema_from_any(sh)
          else
            if t = ph.not_nil!["type"]?.try(&.as_s?)
              fmt = ph.not_nil!["format"]?.try(&.as_s?)
              schema = Schema.new(t, fmt, nil, [] of String, {} of String => Schema, [] of String, nil, nil)
            end
          end

          out << Parameter.new(name.not_nil!, loc.not_nil!, required, desc, schema)
        end

        out
      end

      private def parse_request_body(op_h : Hash(String, JSON::Any)) : RequestBody?
        if @doc.version == Version::OpenAPI30 || @doc.version == Version::OpenAPI31
          rb = op_h["requestBody"]?.try(&.as_h?)
          if rb.nil?
            return nil
          end
          rb = rb.not_nil!

          required = rb["required"]?.try(&.as_bool?) || false
          content = rb["content"]?.try(&.as_h?)
          if content.nil?
            return nil
          end
          content = content.not_nil!

          if app_json = content["application/json"]?.try(&.as_h?)
            if s_any = app_json["schema"]?
              s = schema_from_any(s_any)
              return RequestBody.new(required, "application/json", s)
            end
          end

          content.each do |ct, v|
            unless ct.ends_with?("+json")
              next
            end
            vh = v.as_h?
            if vh.nil?
              next
            end
            s_any = vh.not_nil!["schema"]?
            if s_any.nil?
              next
            end
            s = schema_from_any(s_any.not_nil!)
            return RequestBody.new(required, ct, s)
          end

          return nil
        end

        params = op_h["parameters"]?.try(&.as_a?)
        if params.nil?
          return nil
        end
        params.not_nil!.each do |p_any|
          ph = p_any.as_h?
          if ph.nil?
            next
          end
          unless ph.not_nil!["in"]?.try(&.as_s?) == "body"
            next
          end
          required = ph.not_nil!["required"]?.try(&.as_bool?) || false
          s_any = ph.not_nil!["schema"]?
          if s_any.nil?
            next
          end
          s = schema_from_any(s_any.not_nil!)
          return RequestBody.new(required, "application/json", s)
        end

        nil
      end

      private def first_line(s : String) : String
        line = s.lines.first?
        if line.nil?
          return s.strip
        end
        line.not_nil!.strip
      end
    end
  end
end
