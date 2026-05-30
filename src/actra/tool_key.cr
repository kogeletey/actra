require "uri"

module Actra
  module ToolKey
    def self.for(tool_ref : String) : String
      if tool_ref.starts_with?("registry:")
        return tool_ref
      end

      if tool_ref.includes?("://")
        uri = URI.parse(tool_ref)
        host = uri.host
        return tool_ref unless host
        return uri.port ? "#{host}:#{uri.port}" : host
      end

      tool_ref.strip.chomp("/")
    end
  end
end

