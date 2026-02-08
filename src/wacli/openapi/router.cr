require "json"
require "./document"

module Wacli::OpenAPI
  struct Operation
    getter method : String
    getter path_template : String
    getter path_param_names : Array(String)
    getter path_param_values : Array(String)

    def initialize(@method : String, @path_template : String, @path_param_names : Array(String), @path_param_values : Array(String))
    end
  end

  module Router
    def self.match(doc : Document, method : String, tokens : Array(String)) : Operation
      raise "missing path tokens" if tokens.empty?

      paths_h = doc.raw["paths"].as_h

      matches = [] of Operation
      paths_h.each do |path_template, path_item|
        next unless path_item.as_h?
        next unless has_method?(path_item, method)
        op = match_path_template(path_template, tokens, method)
        matches << op if op
      end

      if matches.empty?
        raise "no matching operation for #{method.upcase} /#{tokens.join("/")}"
      end
      if matches.size > 1
        raise "ambiguous operation match for #{method.upcase} /#{tokens.join("/")}"
      end
      matches[0]
    end

    def self.list_operations(doc : Document) : Array(String)
      out = [] of String
      doc.raw["paths"].as_h.each do |path, item|
        next unless h = item.as_h?
        h.keys.each do |k|
          next if k == "parameters"
          kk = k.downcase
          next unless {"get", "post", "put", "patch", "delete", "head", "options"}.includes?(kk)
          out << "#{kk.upcase} #{path}"
        end
      end
      out.sort
    end

    private def self.has_method?(path_item : JSON::Any, method : String) : Bool
      h = path_item.as_h?
      return false unless h
      h.has_key?(method.downcase)
    end

    private def self.match_path_template(path_template : String, tokens : Array(String), method : String) : Operation?
      t_segs = split_path(path_template)
      return nil unless t_segs.size == tokens.size

      names = [] of String
      values = [] of String

      t_segs.each_with_index do |seg, i|
        tok = tokens[i]
        if seg.starts_with?("{") && seg.ends_with?("}") && seg.size >= 3
          names << seg[1, seg.size - 2]
          values << tok
        else
          return nil unless seg == tok
        end
      end

      Operation.new(method.downcase, path_template, names, values)
    end

    private def self.split_path(path : String) : Array(String)
      path = path.starts_with?("/") ? path[1..] : path
      return [] of String if path.empty?
      path.split("/")
    end
  end
end
