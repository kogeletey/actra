require "json"
require "./document"

module Wacli::OpenAPI
  struct Report
    getter ok : Bool
    getter exit_code : Int32
    getter version : Version?
    getter errors : Array(String)
    getter warnings : Array(String)

    def initialize(@ok : Bool, @exit_code : Int32, @version : Version?, @errors : Array(String), @warnings : Array(String))
    end

    def to_text : String
      String.build do |io|
        if version
          io.puts "version: #{version_string}"
        else
          io.puts "version: unknown"
        end
        io.puts "ok: #{ok}"
        if errors.any?
          io.puts "errors:"
          errors.each { |e| io.puts "  - #{e}" }
        end
        if warnings.any?
          io.puts "warnings:"
          warnings.each { |w| io.puts "  - #{w}" }
        end
      end
    end

    private def version_string : String
      case version
      when Version::Swagger2 then "2.0"
      when Version::OpenAPI30 then "3.0"
      when Version::OpenAPI31 then "3.1"
      else "unknown"
      end
    end
  end

  module Compat
    def self.validate(doc : Document) : Report
      errors = [] of String
      warnings = [] of String

      paths = doc.raw["paths"]?
      unless paths && paths.as_h?
        errors << "missing or invalid 'paths' object"
      end

      # Future: deeper checks. For v0.1 we only require parseable JSON + paths.
      ok = errors.empty?
      exit_code =
        if ok
          0
        else
          # Distinguish "valid JSON but unsupported" (2) from "invalid JSON" (3) at the CLI layer.
          3
        end

      Report.new(ok, exit_code, doc.version, errors, warnings)
    end
  end
end

