require "json"

module Wacli::Interactive
  class JsonBuilder
    @root = {} of String => JSON::Any

    def set_pointer(pointer : String, value : JSON::Any) : Nil
      raise PromptError.new("invalid JSON pointer: #{pointer}") unless pointer.starts_with?("/")
      parts = pointer.split("/")[1..].map { |p| unescape(p) }
      raise PromptError.new("empty JSON pointer: #{pointer}") if parts.empty?

      cur = @root
      parts.each_with_index do |key, idx|
        if idx == parts.size - 1
          cur[key] = value
          break
        end

        if existing = cur[key]?
          h = existing.as_h?
          unless h
            # Overwrite non-object with object if we need to descend.
            h = {} of String => JSON::Any
            cur[key] = JSON::Any.new(h)
          end
          cur = h
        else
          h = {} of String => JSON::Any
          cur[key] = JSON::Any.new(h)
          cur = h
        end
      end
    end

    def to_json : String
      JSON::Any.new(@root).to_json
    end

    private def unescape(s : String) : String
      s.gsub("~1", "/").gsub("~0", "~")
    end
  end
end

