require "json"
require "../render/config"
require "./document"

module Wacli::OpenAPI
  module Hints
    # Best-effort; only supports OpenAPI 3.x and inline schemas (no $ref resolution in v0.2).
    def self.fields_for(doc : Document, method : String, path_template : String) : Array(Wacli::Render::FieldRule)
      return [] of Wacli::Render::FieldRule unless doc.version == Version::OpenAPI30 || doc.version == Version::OpenAPI31

      paths = doc.raw["paths"]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule
      path_item = paths[path_template]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule
      op = path_item[method.downcase]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule

      rb = op["requestBody"]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule
      content = rb["content"]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule
      app_json = content["application/json"]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule
      schema = app_json["schema"]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule
      props = schema["properties"]?.try(&.as_h?) || return [] of Wacli::Render::FieldRule

      required = [] of String
      if req = schema["required"]?.try(&.as_a?)
        required = req.compact_map(&.as_s?)
      end

      out = [] of Wacli::Render::FieldRule
      props.each do |name, prop_any|
        next unless ph = prop_any.as_h?

        prompt = name
        kind = Wacli::Render::FieldKind::String
        enum_values = [] of String

        if ev = ph["enum"]?.try(&.as_a?)
          enum_values = ev.compact_map(&.as_s?)
          kind = Wacli::Render::FieldKind::Enum if enum_values.any?
        elsif t = ph["type"]?.try(&.as_s?)
          if t == "boolean"
            kind = Wacli::Render::FieldKind::Boolean
          end
        end

        if fmt = ph["format"]?.try(&.as_s?)
          if fmt == "date-time"
            kind = Wacli::Render::FieldKind::DateTime
          elsif fmt == "binary"
            kind = Wacli::Render::FieldKind::File
          end
        end

        out << Wacli::Render::FieldRule.new(
          pointer: "/#{escape_ptr(name)}",
          kind: kind,
          prompt: prompt,
          required: required.includes?(name),
          enum_values: enum_values
        )
      end

      out
    rescue
      [] of Wacli::Render::FieldRule
    end

    private def self.escape_ptr(s : String) : String
      s.gsub("~", "~0").gsub("/", "~1")
    end
  end
end

