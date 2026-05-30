require "json"
require "file_utils"
require "random/secure"
require "set"
require "time"

require "./permission"

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

    def permission_allowlist : Array(PermissionAllowEntry)
      permission_decision_map.compact_map do |_key, pair|
        pair[0] == "allow" ? pair[1] : nil
      end
    end

    def append_permission_allow(tool : String, pattern : String) : Nil
      return if permission_allowlist.any? { |entry| entry.tool == tool && entry.pattern == pattern }

      append_entry("permissionAllow") do |json|
        json.field "tool", tool
        json.field "pattern", pattern
      end
    end

    def append_permission_revoke(tool : String, pattern : String) : Nil
      append_entry("permissionRevoke") do |json|
        json.field "tool", tool
        json.field "pattern", pattern
      end
    end

    def permission_denials : Array(PermissionAllowEntry)
      permission_decision_map.compact_map do |_key, pair|
        pair[0] == "deny" ? pair[1] : nil
      end
    end

    def permission_decisions : Array(Tuple(String, PermissionAllowEntry))
      permission_decision_map.values
    end

    def append_permission_deny(tool : String, pattern : String) : Nil
      append_entry("permissionDeny") do |json|
        json.field "tool", tool
        json.field "pattern", pattern
      end
    end

    def append_permission_clear : Nil
      append_entry("permissionClear") do |_json|
      end
    end

    private def permission_decision_map : Hash(String, Tuple(String, PermissionAllowEntry))
      entries = {} of String => Tuple(String, PermissionAllowEntry)
      return entries unless File.exists?(path)

      File.read_lines(path).each do |line|
        next if line.strip.empty?
        any = JSON.parse(line)
        type = any["type"]?.try(&.as_s?)
        if type == "permissionClear"
          entries.clear
          next
        end
        next unless type == "permissionAllow" || type == "permissionRevoke" || type == "permissionDeny"
        tool = any["tool"]?.try(&.as_s?)
        pattern = any["pattern"]?.try(&.as_s?)
        next unless tool && pattern
        tool_value = tool.not_nil!
        pattern_value = pattern.not_nil!
        key = "#{tool_value}\0#{pattern_value}"

        case type
        when "permissionAllow"
          entries[key] = {"allow", PermissionAllowEntry.new(tool_value, pattern_value)}
        when "permissionDeny"
          entries[key] = {"deny", PermissionAllowEntry.new(tool_value, pattern_value)}
        when "permissionRevoke"
          entries.delete(key)
        end
      rescue
      end

      entries
    end

    def permission_requests : Array(PermissionRequest)
      return [] of PermissionRequest unless File.exists?(path)
      File.read_lines(path).compact_map do |line|
        next if line.strip.empty?
        any = JSON.parse(line)
        next unless any["type"]?.try(&.as_s?) == "permissionRequest"
        tool = any["tool"]?.try(&.as_s?)
        input_key = any["input_key"]?.try(&.as_s?)
        next unless tool && input_key
        PermissionRequest.new(
          tool.not_nil!,
          input_key.not_nil!,
          any["path"]?.try(&.as_s?),
          any["command"]?.try(&.as_s?),
          any["reason"]?.try(&.as_s?),
          any["count"]?.try(&.as_i?)
        )
      rescue
        nil
      end
    end

    def pending_permission_requests : Array(PermissionRequest)
      allowlist = permission_allowlist
      denials = permission_denials
      pending = permission_requests.reject do |request|
        allowlist.any? { |entry| entry.matches?(request) } ||
          denials.any? { |entry| entry.matches?(request) }
      end
      unique_permission_requests(pending)
    end

    private def unique_permission_requests(requests : Array(PermissionRequest)) : Array(PermissionRequest)
      seen = Set(String).new
      requests.select do |request|
        key = "#{request.tool}\0#{request.input_key}\0#{request.path}\0#{request.command}\0#{request.reason}"
        next false if seen.includes?(key)
        seen << key
        true
      end
    end

    def append_permission_request(request : PermissionRequest) : Nil
      append_entry("permissionRequest") do |json|
        json.field "tool", request.tool
        json.field "input_key", request.input_key
        json.field "path", request.path if request.path
        json.field "command", request.command if request.command
        json.field "reason", request.reason if request.reason
        json.field "count", request.count if request.count
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
