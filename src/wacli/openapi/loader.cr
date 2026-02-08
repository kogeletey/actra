require "http/client"
require "json"
require "uri"

require "./document"

module Wacli::OpenAPI
  class UnsupportedVersionError < Exception
  end

  module Loader
    def self.load_any(file_or_url : String) : Document
      if file_or_url.starts_with?("http://") || file_or_url.starts_with?("https://")
        load_url(file_or_url)
      else
        load_file(file_or_url)
      end
    end

    def self.load_file(path : String) : Document
      json_text = File.read(path)
      load_json(json_text)
    end

    def self.load_url(url : String) : Document
      uri = URI.parse(url)
      HTTP::Client.get(uri) do |resp|
        unless resp.status_code >= 200 && resp.status_code < 300
          raise "failed to fetch: #{url} (HTTP #{resp.status_code})"
        end
        load_json(resp.body_io.gets_to_end)
      end
    end

    def self.fetch_text(url : String) : String
      uri = URI.parse(url)
      HTTP::Client.get(uri) do |resp|
        unless resp.status_code >= 200 && resp.status_code < 300
          raise "failed to fetch: #{url} (HTTP #{resp.status_code})"
        end
        resp.body_io.gets_to_end
      end
    end

    def self.load_json(json_text : String) : Document
      any = JSON.parse(json_text)
      detect(any)
    end

    def self.detect(any : JSON::Any) : Document
      if (v = any["swagger"]?.try(&.as_s?)) && v.starts_with?("2.")
        return Document.new(Version::Swagger2, any)
      end

      if (v = any["openapi"]?.try(&.as_s?)) && v.starts_with?("3.")
        return Document.new(v.starts_with?("3.1") ? Version::OpenAPI31 : Version::OpenAPI30, any)
      end

      raise UnsupportedVersionError.new("unsupported OpenAPI version (expected 'swagger': '2.x' or 'openapi': '3.x')")
    end
  end
end
