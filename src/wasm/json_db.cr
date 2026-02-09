require "json"
require "file_utils"

module Wacli::Wasm
  # Tiny JSON-file "db" intended for WASI.
  # Schema (v1):
  # {
  #   "schema": 1,
  #   "reports": { "<key>": { "openapiVersion": "3.0", "report": "..." } }
  # }
  struct JsonDb
    SCHEMA = 1

    struct Report
      getter openapi_version : String
      getter report : String

      def initialize(@openapi_version : String, @report : String)
      end
    end

    getter reports : Hash(String, Report)

    def initialize(@reports : Hash(String, Report))
    end

    def self.load(path : String) : JsonDb
      return JsonDb.new(Hash(String, Report).new) unless File.exists?(path)

      any = JSON.parse(File.read(path))
      schema = any["schema"]?.try(&.as_i?) || 0
      raise "unsupported db schema: #{schema}" unless schema == SCHEMA

      reports = Hash(String, Report).new
      (any["reports"]?.try(&.as_h?) || {} of String => JSON::Any).each do |k, v|
        next unless vh = v.as_h?
        openapi_version = vh["openapiVersion"]?.try(&.as_s?) || "unknown"
        report = vh["report"]?.try(&.as_s?) || ""
        reports[k] = Report.new(openapi_version, report)
      end

      JsonDb.new(reports)
    end

    def save(path : String) : Nil
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless dir.empty? || dir == "."

      tmp = "#{path}.tmp"
      File.write(tmp, to_json)
      File.rename(tmp, path)
    end

    def set_report(key : String, openapi_version : String, report : String) : Nil
      reports[key] = Report.new(openapi_version, report)
    end

    def get_report(key : String) : Report?
      reports[key]?
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          json.field "schema", SCHEMA
          json.field "reports" do
            json.object do
              reports.each do |k, v|
                json.field k do
                  json.object do
                    json.field "openapiVersion", v.openapi_version
                    json.field "report", v.report
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

