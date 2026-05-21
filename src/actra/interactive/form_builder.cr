require "../render/config"
require "../openapi/dto"

module Actra::Interactive
  module FormBuilder
    def self.fields_for_schema(schema : OpenAPI::Dto::Schema, pointer_prefix : String = "") : Array(Actra::Render::FieldRule)
      out = [] of Actra::Render::FieldRule

      if schema.objectish?
        schema.properties.keys.sort.each do |name|
          child = schema.properties[name]
          ptr = join_ptr(pointer_prefix, name)
          out.concat(fields_for_node(child, ptr, name, schema.required.includes?(name)))
        end
      else
        # Non-object root bodies would require writing at the JSON pointer root ("/"),
        # which our JsonBuilder doesn't support. Defer to --json for these cases.
      end

      out
    end

    private def self.fields_for_node(schema : OpenAPI::Dto::Schema, pointer : String, name : String, required : Bool) : Array(Actra::Render::FieldRule)
      # If this node is an object with known properties, recurse (so we can build nested objects).
      if schema.objectish? && schema.properties.any?
        out = [] of Actra::Render::FieldRule
        schema.properties.keys.sort.each do |child_name|
          child = schema.properties[child_name]
          child_ptr = join_ptr(pointer, child_name)
          out.concat(fields_for_node(child, child_ptr, "#{name}.#{child_name}", schema.required.includes?(child_name)))
        end
        out
      else
        kind = kind_for(schema)
        prompt = prompt_for(name, schema)
        enum_values = schema.enum_values

        [Actra::Render::FieldRule.new(
          pointer: pointer,
          kind: kind,
          prompt: prompt,
          required: required,
          enum_values: enum_values
        )]
      end
    end

    private def self.kind_for(schema : OpenAPI::Dto::Schema) : Actra::Render::FieldKind
      if schema.enum_values.any?
        return Actra::Render::FieldKind::Enum
      end

      t = schema.type
      fmt = schema.format

      if t == "boolean"
        return Actra::Render::FieldKind::Boolean
      end

      if t == "string" && fmt == "date-time"
        return Actra::Render::FieldKind::DateTime
      end

      if t == "string" && fmt == "binary"
        return Actra::Render::FieldKind::File
      end

      # Numbers/arrays/unknown: ask for JSON so we don't accidentally stringify.
      if t == "integer" || t == "number" || schema.arrayish? || schema.ref || t.nil?
        return Actra::Render::FieldKind::Json
      end

      Actra::Render::FieldKind::String
    end

    private def self.prompt_for(name : String, schema : OpenAPI::Dto::Schema) : String
      if d = schema.description
        dd = d.lines.first?.try(&.strip) || d.strip
        dd.empty? ? name : "#{name} (#{dd})"
      else
        name
      end
    end

    private def self.join_ptr(prefix : String, name : String) : String
      a = prefix.empty? ? "" : prefix
      seg = escape_ptr(name)
      if a.empty?
        "/#{seg}"
      else
        "#{a}/#{seg}"
      end
    end

    private def self.escape_ptr(s : String) : String
      s.gsub("~", "~0").gsub("/", "~1")
    end
  end
end
