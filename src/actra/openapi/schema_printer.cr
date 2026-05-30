require "./dto"

module Actra::OpenAPI
  module SchemaPrinter
    def self.print(schema : Dto::Schema, io : IO, indent : Int32 = 0, name : String? = nil, required : Bool = false) : Nil
      ind = " " * indent
      if name
        io.puts "#{ind}#{name}: #{describe(schema)}#{required ? " (required)" : ""}"
      else
        io.puts "#{ind}#{describe(schema)}"
      end

      if schema.objectish?
        schema.properties.keys.sort.each do |k|
          v = schema.properties[k]
          print(v, io, indent + 2, k, schema.required.includes?(k))
        end
      elsif schema.arrayish? && (it = schema.items)
        print(it, io, indent + 2, "items", false)
      end
    end

    private def self.describe(schema : Dto::Schema) : String
      if schema.ref
        return "ref #{schema.ref}"
      end

      if schema.enum_values.any?
        return "enum [#{schema.enum_values.join(", ")}]"
      end

      t = schema.type
      fmt = schema.format
      if t && fmt
        "#{t} (#{fmt})"
      elsif t
        t
      elsif schema.objectish?
        "object"
      elsif schema.arrayish?
        "array"
      else
        "unknown"
      end
    end
  end
end

