require "http/client"
require "http/params"
require "json"
require "uri"
require "file_utils"
require "digest/sha256"

require "./xdg"

module Wacli
  struct Response
    getter status_code : Int32
    getter headers : HTTP::Headers
    getter body_bytes : Bytes

    def initialize(@status_code : Int32, @headers : HTTP::Headers, @body_bytes : Bytes)
    end

    def header?(name : String) : String?
      headers[name]?
    end

    def content_type : String?
      header?("Content-Type").try { |v| v.split(";", 2)[0].strip }
    end

    def attachment_filename : String?
      cd = header?("Content-Disposition")
      return nil unless cd
      # Very small parser: looks for filename="<x>" or filename=x
      if m = cd.match(/filename\*=UTF-8''([^;]+)/)
        return URI.decode(m[1])
      end
      if m = cd.match(/filename=\"([^\"]+)\"/)
        return m[1]
      end
      if m = cd.match(/filename=([^;]+)/)
        return m[1].strip
      end
      nil
    end

    def attachment? : Bool
      cd = header?("Content-Disposition")
      return false unless cd
      cd.downcase.includes?("attachment")
    end
  end

  struct Request
    getter method : String
    getter url : String
    getter headers : Array(Tuple(String, String))
    getter body : String?

    def initialize(@method : String, @url : String, @headers : Array(Tuple(String, String)), @body : String?)
    end

    def self.build(
      base_url : String,
      method : String,
      path_template : String,
      path_param_names : Array(String),
      path_param_values : Array(String),
      query : Array(Tuple(String, String)),
      headers : Array(Tuple(String, String)),
      json_body : String?,
      bearer_token : String?,
      bearer_header : String
    ) : Request
      url = join_url(base_url, interpolate_path(path_template, path_param_names, path_param_values))
      url = add_query(url, query) if query.any?

      out_headers = headers.dup
      if bearer_token
        unless out_headers.any? { |h| h[0].downcase == bearer_header.downcase }
          if bearer_header.downcase == "authorization"
            out_headers << {"Authorization", "Bearer #{bearer_token}"}
          else
            out_headers << {bearer_header, bearer_token}
          end
        end
      end

      if json_body
        unless out_headers.any? { |h| h[0].downcase == "content-type" }
          out_headers << {"Content-Type", "application/json"}
        end
      end

      new(method.downcase, url, out_headers, json_body)
    end

    def to_dry_run : String
      String.build do |io|
        io.puts "#{method.upcase} #{url}"
        headers.each { |(k, v)| io.puts "#{k}: #{v}" }
        if body
          io.puts
          io.puts body
        end
      end
    end

    def execute : Response
      uri = URI.parse(url)
      HTTP::Client.exec(method.upcase, uri, headers: to_http_headers, body: body) do |resp|
        buf = IO::Memory.new
        IO.copy(resp.body_io, buf)
        Response.new(resp.status_code, resp.headers, buf.to_slice)
      end
    end

    private def to_http_headers : HTTP::Headers
      h = HTTP::Headers.new
      headers.each { |(k, v)| h.add(k, v) }
      h
    end

    private def self.interpolate_path(path_template : String, names : Array(String), values : Array(String)) : String
      out = path_template
      names.each_with_index do |n, i|
        v = values[i]? || ""
        out = out.gsub("{#{n}}", URI.encode_path(v))
      end
      out
    end

    private def self.join_url(base : String, path : String) : String
      b = base.ends_with?("/") ? base[0, base.size - 1] : base
      p = path.starts_with?("/") ? path : "/#{path}"
      "#{b}#{p}"
    end

    private def self.add_query(url : String, query : Array(Tuple(String, String))) : String
      uri = URI.parse(url)
      params = HTTP::Params.parse(uri.query || "")
      query.each { |(k, v)| params.add(k, v) }
      uri.query = params.to_s
      uri.to_s
    end
  end

  module Cache
    def self.ain_path(tool_key : String) : String
      File.join(Xdg.cache_dir, "ains", "#{safe_name(tool_key)}.json")
    end

    private def self.safe_name(s : String) : String
      s.gsub(/[^A-Za-z0-9._-]/, "_")
    end
  end

  class Lock
    getter ains : Hash(String, Hash(String, String))

    def initialize(@ains : Hash(String, Hash(String, String)))
    end

    def self.load : Lock
      path = Xdg.lock_path
      return new({} of String => Hash(String, String)) unless File.exists?(path)
      any = JSON.parse(File.read(path))
      ains = {} of String => Hash(String, String)
      if ah = any["ains"]?.try(&.as_h?)
        ah.each do |tool, obj|
          next unless obj.as_h?
          h = {} of String => String
          obj.as_h.each { |k, v| h[k] = v.as_s }
          ains[tool] = h
        end
      end
      new(ains)
    end

    def set_ain(tool_ref : String, source : String, install_path : String, openapi_version : String, integrity : String) : Nil
      tool = tool_ref
      ains[tool] = {
        "integrity"     => integrity,
        "source"        => source,
        "installPath"   => install_path,
        "openapiVersion"=> openapi_version,
      }
    end

    def get_ain(tool_key : String) : Hash(String, String)?
      ains[tool_key]?
    end

    def save : Nil
      FileUtils.mkdir_p(Xdg.config_dir)
      File.write(Xdg.lock_path, to_json)
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          json.field "fileVersion", 1
          json.field "ains" do
            json.object do
              ains.each do |tool, obj|
                json.field tool do
                  json.object do
                    obj.each { |k, v| json.field k, v }
                  end
                end
              end
            end
          end
        end
      end
    end

    def self.sha256(text : String) : String
      Digest::SHA256.hexdigest(text)
    end
  end
end
