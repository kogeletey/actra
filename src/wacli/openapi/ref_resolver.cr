require "json"

require "./document"

module Wacli::OpenAPI
  # Local-only JSON Pointer $ref resolver.
  #
  # Supports:
  # - OAS3:   #/components/schemas/...
  # - OAS2:   #/definitions/...
  #
  # Does not fetch external refs.
  class RefResolver
    class ResolveError < Exception
    end

    @max_depth : Int32

    def initialize(@doc : Document, @max_depth : Int32 = 20)
    end

    def resolve_schema_any(schema_any : JSON::Any) : JSON::Any
      resolve_any(schema_any, 0, Set(String).new)
    end

    private def resolve_any(any : JSON::Any, depth : Int32, seen : Set(String)) : JSON::Any
      return any unless h = any.as_h?
      if ref = h["$ref"]?.try(&.as_s?)
        raise ResolveError.new("ref depth exceeded") if depth >= @max_depth
        raise ResolveError.new("ref cycle detected: #{ref}") if seen.includes?(ref)
        seen.add(ref)
        target = lookup_ref(ref)
        return resolve_any(target, depth + 1, seen)
      end
      any
    end

    private def lookup_ref(ref : String) : JSON::Any
      unless ref.starts_with?("#/")
        raise ResolveError.new("external ref not supported: #{ref}")
      end
      parts = ref[2..].split("/")
      cur = @doc.raw
      parts.each do |p|
        key = unescape_ptr(p)
        if h = cur.as_h?
          cur = h[key]? || raise ResolveError.new("ref not found: #{ref}")
        else
          raise ResolveError.new("ref not found: #{ref}")
        end
      end
      cur
    end

    private def unescape_ptr(s : String) : String
      s.gsub("~1", "/").gsub("~0", "~")
    end
  end
end

