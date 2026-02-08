require "http/client"
require "json"
require "uri"
require "file_utils"

require "./tool_key"
require "./xdg"

module Wacli
  class ManifestNotFoundError < Exception
  end

  struct Header
    getter name : String
    getter value : String
    def initialize(@name : String, @value : String); end
  end

  struct Manifest
    getter api : String?
    getter registry : Bool
    getter manifests : Hash(String, String)?
    getter headers : Array(Tuple(String, String))
    getter path_aliases : Hash(String, String)
    getter auth_scheme : String?
    getter token_name : String?

    def initialize(
      @api : String?,
      @registry : Bool,
      @manifests : Hash(String, String)?,
      @headers : Array(Tuple(String, String)),
      @path_aliases : Hash(String, String),
      @auth_scheme : String?,
      @token_name : String?
    )
    end

    def bearer_auth? : Bool
      auth_scheme.try(&.downcase) == "bearer"
    end

    def bearer_header_name : String
      # For v0.1 interpret tokenName as header name if provided; default to Authorization.
      token_name || "Authorization"
    end

    def expand_path_tokens(tokens : Array(String)) : Array(String)
      out = [] of String
      i = 0
      while i < tokens.size
        t = tokens[i]
        if repl = path_aliases[t]?
          segs = repl.starts_with?("/") ? repl[1..].split("/") : repl.split("/")
          j = i + 1
          segs.each do |s|
            next if s.empty?
            if s.starts_with?("{") && s.ends_with?("}") && s.size >= 3
              # Consume subsequent tokens as values for placeholder segments.
              if v = tokens[j]?
                out << v
                j += 1
              else
                out << s
              end
            else
              out << s
            end
          end
          i = j
        else
          out << t
          i += 1
        end
      end
      out
    end

    def self.fetch_tool(tool_ref : String, cfg : Config) : Manifest
      # Local override: ~/.config/wacli/tools/<tool>.json
      if (local = local_override_path(tool_ref)) && File.exists?(local)
        return parse(File.read(local))
      end

      # Local file manifest: wacli ./path/to/wacli.json ...
      if File.exists?(tool_ref) && File.file?(tool_ref)
        return parse(File.read(tool_ref))
      end

      # Local directory manifest: wacli ./some/dir ...
      if File.exists?(tool_ref) && File.directory?(tool_ref)
        ["#{tool_ref}/.well-known/wacli.json", "#{tool_ref}/.well-know/wacli.json"].each do |p|
          return parse(File.read(p)) if File.exists?(p)
        end
        raise ManifestNotFoundError.new("manifest not found in directory #{tool_ref}")
      end

      if tool_ref.starts_with?("registry:")
        name = tool_ref.split(":", 2)[1]
        registry_url = cfg.uri_schemes["registry"]? || raise "missing uri_schemes.registry in config"
        reg = fetch_from_base(registry_url)
        raise "registry manifest missing 'manifests'" unless reg.manifests
        path = reg.manifests.not_nil![name]? || raise "registry has no entry for #{name}"
        return parse(fetch_text(path))
      end

      base = normalize_base(tool_ref)
      fetch_from_base(base)
    end

    def self.fetch_from_base(base_url : String) : Manifest
      body = nil.as(String?)
      manifest_urls(base_url).each do |u|
        resp = HTTP::Client.get(URI.parse(u))
        if resp.status_code >= 200 && resp.status_code < 300
          body = resp.body
          break
        end
        if resp.status_code == 404
          next
        end
        raise "failed to fetch manifest: #{u} (HTTP #{resp.status_code})"
      end
      raise ManifestNotFoundError.new("manifest not found at .well-known for #{base_url}") unless body
      parse(body.not_nil!)
    end

    def self.manifest_urls(base_url : String) : Array(String)
      b = base_url.ends_with?("/") ? base_url[0, base_url.size - 1] : base_url
      [
        "#{b}/.well-known/wacli.json",
        "#{b}/.well-know/wacli.json",
      ]
    end

    def self.normalize_base(tool_ref : String) : String
      if tool_ref.includes?("://")
        tool_ref
      else
        "https://#{tool_ref}"
      end
    end

    def self.local_override_path(tool_ref : String) : String?
      begin
        key = ToolKey.for(tool_ref)
        File.join(Xdg.tools_dir, "#{safe_name(key)}.json")
      rescue
        nil
      end
    end

    private def self.safe_name(s : String) : String
      s.gsub(/[^A-Za-z0-9._-]/, "_")
    end

    def self.fetch_text(url : String) : String
      HTTP::Client.get(URI.parse(url)) do |resp|
        unless resp.status_code >= 200 && resp.status_code < 300
          raise "failed to fetch: #{url} (HTTP #{resp.status_code})"
        end
        resp.body_io.gets_to_end
      end
    end

    def self.parse(json_text : String) : Manifest
      any = JSON.parse(json_text)
      api = any["api"]?.try(&.as_s?)
      registry = any["registry"]?.try(&.as_bool?) || false

      manifests = nil.as(Hash(String, String)?)
      if mh = any["manifests"]?.try(&.as_h?)
        m = {} of String => String
        mh.each do |name, obj|
          path = obj["path"]?.try(&.as_s?) || next
          m[name] = path
        end
        manifests = m
      end

      headers = [] of Tuple(String, String)
      path_aliases = {} of String => String
      auth_scheme = nil.as(String?)
      token_name = nil.as(String?)

      if settings = any["settings"]?.try(&.as_h?)
        if hs = settings["headers"]?.try(&.as_a?)
          hs.each do |h|
            name = h["name"]?.try(&.as_s?)
            value = h["value"]?.try(&.as_s?)
            headers << {name.not_nil!, value.not_nil!} if name && value
          end
        end

        if aliases = settings["aliases"]?.try(&.as_a?)
          aliases.each do |a|
            next unless a.as_h?
            type = a["type"]?.try(&.as_s?)
            next unless type == "path"
            content = a["content"]?.try(&.as_s?)
            next unless content

            al = a["alias"]?
            if s = al.try(&.as_s?)
              path_aliases[s] = content
            elsif arr = al.try(&.as_a?)
              if arr.size >= 1
                path_aliases[arr[0].as_s] = content
              end
              if arr.size >= 2
                path_aliases[arr[1].as_s] = content
              end
            end
          end
        end

        if auth = settings["auth"]?.try(&.as_h?)
          auth_scheme = auth["scheme"]?.try(&.as_s?)
          token_name = auth["tokenName"]?.try(&.as_s?)
        end
      end

      new(api, registry, manifests, headers, path_aliases, auth_scheme, token_name)
    end
  end
end
