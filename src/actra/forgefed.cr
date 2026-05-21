require "base64"
require "digest/sha256"
require "http/client"
require "json"
require "random/secure"
require "uri"

require "./config"

module Actra
  module ForgeFed
    CONTEXT = [
      "https://www.w3.org/ns/activitystreams",
      "https://w3id.org/security/v2",
      "https://forgefed.org/ns",
    ]

    struct Delivery
      getter method : String
      getter url : String
      getter headers : HTTP::Headers
      getter body : String

      def initialize(@method : String, @url : String, @headers : HTTP::Headers, @body : String)
      end

      def dry_run : String
        String.build do |io|
          io.puts "#{method} #{url}"
          headers.each { |name, values| values.each { |value| io.puts "#{name}: #{redact_header(name, value)}" } }
          io.puts
          io.puts body
        end
      end

      private def redact_header(name : String, value : String) : String
        name.downcase == "authorization" ? "Bearer <redacted>" : value
      end
    end

    def self.build_ticket_activity(server : ServerConfig, actor : ActorConfig?, summary : String, content : String, inbox : String? = nil, sign : Bool = true) : Delivery
      target_inbox = absolute_url(server.base_url, inbox || actor.try(&.inbox) || server.inbox)
      work_type = actor.try(&.work_type) || "task"
      activity_id = "urn:actra:activity:#{Random::Secure.hex(16)}"
      ticket_id = "urn:actra:ticket:#{Random::Secure.hex(16)}"

      body = {
        "@context" => CONTEXT,
        "id"       => activity_id,
        "type"     => "Create",
        "actor"    => server.actor_id,
        "to"       => [absolute_url(server.base_url, actor.try(&.inbox) || server.inbox)],
        "object"   => {
          "@context"     => CONTEXT,
          "id"           => ticket_id,
          "type"         => "Ticket",
          "context"      => "#{server.base_url}/tracker/global",
          "attributedTo" => server.actor_id,
          "summary"      => summary,
          "content"      => content,
          "mediaType"    => "text/plain",
          "taskType"     => work_type,
          "workType"     => work_type,
          "source"       => {
            "content"   => content,
            "mediaType" => "text/plain",
          },
        },
      }.to_json

      headers_for(server, target_inbox, body, sign)
    end

    def self.post(delivery : Delivery) : HTTP::Client::Response
      HTTP::Client.post(delivery.url, headers: delivery.headers, body: delivery.body)
    end

    def self.absolute_url(base_url : String, path_or_url : String) : String
      return path_or_url if path_or_url.starts_with?("http://") || path_or_url.starts_with?("https://")

      base = base_url.gsub(/\/+$/, "")
      path = path_or_url.starts_with?("/") ? path_or_url : "/#{path_or_url}"
      "#{base}#{path}"
    end

    private def self.headers_for(server : ServerConfig, url : String, body : String, sign : Bool) : Delivery
      uri = URI.parse(url)
      digest = "SHA-256=#{Base64.strict_encode(Digest::SHA256.digest(body))}"
      date = Time.utc.to_rfc2822
      host = uri.host || raise "missing host for #{url}"
      target = uri.path.empty? ? "/" : uri.path
      target += "?#{uri.query}" if uri.query

      headers = HTTP::Headers{
        "Accept"       => "application/activity+json, application/json",
        "Content-Type" => "application/activity+json",
        "Date"         => date,
        "Digest"       => digest,
        "Host"         => host,
      }

      if sign && (signature = server.http_signature)
        signing_string = [
          "(request-target): post #{target}",
          "host: #{host}",
          "date: #{date}",
          "digest: #{digest}",
        ].join("\n")
        headers["Signature"] = signature_header(signature, signing_string)
      end

      if lefine_host?(host) && (token = ENV["LEFINE_TOKEN"]?) && !token.empty?
        headers["Authorization"] = "Bearer #{token}"
      end

      Delivery.new("POST", url, headers, body)
    end

    private def self.lefine_host?(host : String) : Bool
      host == "lefine.pro" || host.ends_with?(".lefine.pro")
    end

    private def self.signature_header(config : HttpSignatureConfig, signing_string : String) : String
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run(
        "openssl",
        ["dgst", "-sha256", "-sign", config.private_key_path],
        input: IO::Memory.new(signing_string),
        output: output,
        error: error
      )
      raise "openssl signing failed: #{error.to_s.strip}" unless status.success?

      signature = Base64.strict_encode(output.to_slice)
      %(keyId="#{config.key_id}",algorithm="#{config.algorithm}",headers="(request-target) host date digest",signature="#{signature}")
    end
  end
end
