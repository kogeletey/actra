require "json"

module Wacli::OpenAPI
  enum Version
    Swagger2
    OpenAPI30
    OpenAPI31
  end

  struct Document
    getter version : Version
    getter raw : JSON::Any

    def initialize(@version : Version, @raw : JSON::Any)
    end

    def version_string : String
      case version
      when Version::Swagger2 then "2.0"
      when Version::OpenAPI30 then "3.0"
      when Version::OpenAPI31 then "3.1"
      else "unknown"
      end
    end

    def paths_any : JSON::Any
      raw["paths"]? || JSON::Any.new(nil)
    end
  end
end
