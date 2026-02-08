require "json"
require "uri"

require "./document"

module Wacli::OpenAPI
  module BaseUrl
    def self.compute(doc : Document, tool_ref : String) : String
      tool = tool_base(tool_ref)

      case doc.version
      when Version::Swagger2
        host = doc.raw["host"]?.try(&.as_s?)
        return tool.to_s unless host

        base_path = doc.raw["basePath"]?.try(&.as_s?) || ""
        base_path = "" if base_path == "/"
        base_path = "/#{base_path}" unless base_path.empty? || base_path.starts_with?("/")

        scheme = doc.raw["schemes"]?.try(&.as_a?)?.first?.try(&.as_s?) || tool.scheme || "https"
        "#{scheme}://#{host}#{base_path}"
      when Version::OpenAPI30, Version::OpenAPI31
        if servers = doc.raw["servers"]?.try(&.as_a?)
          if url = servers.first?["url"]?.try(&.as_s?)
            return url
          end
        end
        tool.to_s
      end
    end

    private def self.tool_base(tool_ref : String) : URI
      s =
        if tool_ref.includes?("://")
          tool_ref
        else
          "https://#{tool_ref}"
        end
      URI.parse(s)
    end
  end
end
