require "uri"
require "file_utils"
require "time"

require "./config"
require "./manifest"
require "./openapi/loader"
require "./request"
require "./tool_key"

module Actra
  struct ToolResolved
    getter api_url : String
    getter manifest : Manifest
    getter source : String  # "ain" | "manifest" | "fallback"

    def initialize(@api_url : String, @manifest : Manifest, @source : String)
    end
  end

  module ToolResolver
    def self.resolve(tool_ref : String, cfg : Config) : ToolResolved
      key = ToolKey.for(tool_ref)

      # 1) Prefer local installed/cached specs from `ain` (no network).
      lock = Lock.load
      if e = lock.get_ain(key)
        if p = e["installPath"]?
          if File.exists?(p)
            # Keep local manifest overrides (aliases/headers/auth), if present.
            manifest = try_local_manifest(tool_ref, cfg) || Manifest.new(nil, false, nil, [] of Tuple(String, String), {} of String => String, nil, nil)
            return ToolResolved.new(p, manifest, "ain")
          end
        end
      end

      # Back-compat: old cache naming used raw tool_ref.
      old_cache = Cache.ain_path(tool_ref)
      if File.exists?(old_cache)
        manifest = try_local_manifest(tool_ref, cfg) || Manifest.new(nil, false, nil, [] of Tuple(String, String), {} of String => String, nil, nil)
        return ToolResolved.new(old_cache, manifest, "ain")
      end

      # 2) Fetch tool manifest (may use local override/file/dir or network).
      direct_url = tool_ref.starts_with?("http://") || tool_ref.starts_with?("https://")

      begin
        manifest = Manifest.fetch_tool(tool_ref, cfg)
        if api = manifest.api
          return ToolResolved.new(api, manifest, "manifest")
        end
      rescue ManifestNotFoundError
        # Try fallback below
      rescue ex
        # For explicit http(s) tool refs, tolerate manifest fetch errors and
        # still attempt direct OpenAPI fallback paths.
        raise ex unless direct_url
      end

      # Local directory fallback: ./dir/openapi.json or ./dir/swagger.json
      if File.exists?(tool_ref) && File.directory?(tool_ref)
        ["#{tool_ref}/openapi.json", "#{tool_ref}/swagger.json"].each do |p|
          next unless File.exists?(p)
          OpenAPI::Loader.load_file(p)
          return ToolResolved.new(p, Manifest.new(p, false, nil, [] of Tuple(String, String), {} of String => String, nil, nil), "fallback")
        end
      end

      base = Manifest.normalize_base(tool_ref)
      if u = fallback_openapi_url(base, direct_url)
        return ToolResolved.new(u, Manifest.new(u, false, nil, [] of Tuple(String, String), {} of String => String, nil, nil), "fallback")
      end

      raise "no manifest and no fallback OpenAPI JSON found for #{tool_ref}"
    end

    def self.fallback_urls(base_url : String) : Array(String)
      b = base_url.ends_with?("/") ? base_url[0, base_url.size - 1] : base_url
      [
        "#{b}/openapi.json",
        "#{b}/swagger.json",
      ]
    end

    private def self.fallback_openapi_url(base_url : String, retriable : Bool) : String?
      # Direct URL refs often target ad-hoc/local dev servers; allow brief retries
      # so startup races don't fail resolution before /openapi.json is ready.
      attempts = retriable ? 5 : 1
      attempt = 0
      while attempt < attempts
        fallback_urls(base_url).each do |u|
          begin
            # Load+detect to ensure it is a real OpenAPI JSON.
            OpenAPI::Loader.load_url(u)
            return u
          rescue
            next
          end
        end

        attempt += 1
        break if attempt >= attempts
        sleep 50.milliseconds
      end
      nil
    end

    private def self.try_local_manifest(tool_ref : String, cfg : Config) : Manifest?
      # This only checks local sources already supported by Manifest.fetch_tool before it would go network.
      if (local = Manifest.local_override_path(tool_ref)) && File.exists?(local)
        return Manifest.parse(File.read(local))
      end
      if File.exists?(tool_ref) && File.file?(tool_ref)
        return Manifest.parse(File.read(tool_ref))
      end
      if File.exists?(tool_ref) && File.directory?(tool_ref)
        [
          "#{tool_ref}/.well-known/actra.json",
          "#{tool_ref}/.well-know/actra.json",
          "#{tool_ref}/.well-known/wacli.json",
          "#{tool_ref}/.well-know/wacli.json",
        ].each do |p|
          return Manifest.parse(File.read(p)) if File.exists?(p)
        end
      end
      nil
    rescue
      nil
    end
  end
end
