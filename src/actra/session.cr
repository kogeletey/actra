require "json"
require "file_utils"
require "random/secure"
require "time"

module Actra
  class AgentSession
    getter id : String
    getter path : String

    def initialize(@id : String, @path : String)
    end

    def self.open(session_dir : String, requested_id : String? = nil) : AgentSession
      FileUtils.mkdir_p(session_dir)
      id = requested_id || new_id
      path = resolve_path(session_dir, id)
      id = File.basename(path, ".jsonl")
      session = new(id, path)
      session.write_header unless File.exists?(path)
      session
    end

    def self.recent(session_dir : String) : AgentSession?
      return nil unless Dir.exists?(session_dir)
      path = Dir.glob(File.join(session_dir, "*.jsonl")).max_by? { |candidate| File.info(candidate).modification_time }
      return nil unless path
      new(File.basename(path, ".jsonl"), path)
    end

    def self.fork(session_dir : String, source_ref : String) : AgentSession
      source = existing(session_dir, source_ref)
      target = open(session_dir)
      File.write(target.path, File.read(source.path))
      target.append_entry("branchSummary") do |json|
        json.field "sourceSession", source.id
      end
      target
    end

    def self.export_html(session_dir : String, source_ref : String, out_path : String?) : String
      session = existing(session_dir, source_ref)
      output = out_path || "#{session.id}.html"
      body = String.build do |html|
        html << "<!doctype html><html><head><meta charset=\"utf-8\"><title>Actra Session "
        html << escape_html(session.id)
        html << "</title><style>body{font-family:system-ui,sans-serif;max-width:900px;margin:40px auto;line-height:1.45}pre{white-space:pre-wrap;background:#f6f8fa;padding:12px;border-radius:6px}.role{font-weight:700;margin-top:24px}</style></head><body>"
        html << "<h1>Actra Session "
        html << escape_html(session.id)
        html << "</h1>"
        session.messages.each do |message|
          html << "<div class=\"role\">"
          html << escape_html(message["role"]?.try(&.as_s?) || "message")
          html << "</div><pre>"
          html << escape_html(message["content"]?.try(&.as_s?) || message.to_json)
          html << "</pre>"
        end
        html << "</body></html>"
      end
      File.write(output, body)
      output
    end

    def self.existing(session_dir : String, ref : String) : AgentSession
      path = resolve_path(session_dir, ref)
      raise "session not found: #{ref}" unless File.exists?(path)
      new(File.basename(path, ".jsonl"), path)
    end

    def append_message(role : String, content : String, parent_id : String? = nil) : String
      entry_id = next_entry_id
      append_json do |json|
        json.object do
          json.field "type", "message"
          json.field "id", entry_id
          json.field "parentId", parent_id
          json.field "timestamp", Time.utc.to_rfc3339
          json.field "role", role
          json.field "content", content
        end
      end
      entry_id
    end

    def messages : Array(JSON::Any)
      return [] of JSON::Any unless File.exists?(path)
      File.read_lines(path).compact_map do |line|
        next if line.strip.empty?
        any = JSON.parse(line)
        any["type"]?.try(&.as_s?) == "message" ? any : nil
      rescue
        nil
      end
    end

    def append_entry(type : String, &block : JSON::Builder ->) : Nil
      append_json do |json|
        json.object do
          json.field "type", type
          json.field "id", next_entry_id
          json.field "timestamp", Time.utc.to_rfc3339
          yield json
        end
      end
    end

    def write_header : Nil
      append_json do |json|
        json.object do
          json.field "type", "session"
          json.field "version", 3
          json.field "id", id
          json.field "timestamp", Time.utc.to_rfc3339
          json.field "cwd", Dir.current
        end
      end
    end

    private def append_json(&block : JSON::Builder ->) : Nil
      File.open(path, "a") do |file|
        JSON.build(file) { |json| yield json }
        file.puts
      end
    end

    private def self.new_id : String
      Random::Secure.hex(16)
    end

    private def self.resolve_path(session_dir : String, ref : String) : String
      expanded = ref.starts_with?("~") ? ref.sub("~", ENV["HOME"]? || "~") : ref
      return expanded if expanded.includes?("/") || expanded.ends_with?(".jsonl")

      exact = File.join(session_dir, "#{expanded}.jsonl")
      return exact if File.exists?(exact)

      matches = Dir.exists?(session_dir) ? Dir.glob(File.join(session_dir, "#{expanded}*.jsonl")) : [] of String
      return matches.first if matches.size == 1
      raise "ambiguous session id: #{ref}" if matches.size > 1

      exact
    end

    private def self.escape_html(text : String) : String
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;")
    end

    private def next_entry_id : String
      Random::Secure.hex(8)
    end
  end
end
