require "json"
require "./document"
require "./errors"

module Wacli::OpenAPI
  module Detector
    def self.detect(any : JSON::Any) : Document
      if (v = any["swagger"]?.try(&.as_s?)) && v.starts_with?("2.")
        return Document.new(Version::Swagger2, any)
      end

      if (v = any["openapi"]?.try(&.as_s?)) && v.starts_with?("3.")
        version = v.starts_with?("3.1") ? Version::OpenAPI31 : Version::OpenAPI30
        return Document.new(version, any)
      end

      raise UnsupportedVersionError.new("unsupported OpenAPI version (expected 'swagger': '2.x' or 'openapi': '3.x')")
    end
  end
end
