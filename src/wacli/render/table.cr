require "json"
require "./config"

module Wacli::Render
  module Table
    def self.render(any : JSON::Any, io : IO, cfg : TableConfig) : Nil
      arr = any.as_a?
      unless arr
        io.puts any.to_json
        return
      end

      rows = arr[0, Math.min(arr.size, cfg.max_rows)]
      if rows.empty?
        io.puts "(empty)"
        return
      end

      if rows.all? { |r| !!r.as_h? }
        render_objects(rows, io, cfg)
      else
        render_primitives(rows, io, cfg)
      end
    end

    private def self.render_primitives(rows : Array(JSON::Any), io : IO, cfg : TableConfig) : Nil
      headers = ["idx", "value"]
      data = rows.map_with_index do |v, i|
        [i.to_s, format_cell(v, cfg)]
      end
      print_table(headers, data, io, cfg)
    end

    private def self.render_objects(rows : Array(JSON::Any), io : IO, cfg : TableConfig) : Nil
      keys = [] of String
      rows.each_with_index do |row_any, idx|
        break if idx >= 50
        h = row_any.as_h? || next
        h.keys.each do |k|
          next if keys.includes?(k)
          keys << k
          break if keys.size >= cfg.max_columns
        end
        break if keys.size >= cfg.max_columns
      end
      keys = keys[0, Math.min(keys.size, cfg.max_columns)]
      headers = keys

      data = rows.map do |row_any|
        h = row_any.as_h? || ({} of String => JSON::Any)
        keys.map do |k|
          v = h[k]?
          v ? format_cell(v, cfg) : ""
        end
      end

      print_table(headers, data, io, cfg)
    end

    private def self.format_cell(v : JSON::Any, cfg : TableConfig) : String
      s =
        if v.as_h? || v.as_a?
          v.to_json
        else
          v.to_s
        end
      s = s.gsub(/\s+/, " ").strip
      if s.size > cfg.max_cell_width
        s[0, cfg.max_cell_width - 3] + "..."
      else
        s
      end
    end

    private def self.print_table(headers : Array(String), rows : Array(Array(String)), io : IO, cfg : TableConfig) : Nil
      widths = headers.map(&.size)
      rows.each do |r|
        r.each_with_index do |cell, i|
          widths[i] = Math.max(widths[i], cell.size)
        end
      end

      sep = "+" + widths.map { |w| "-" * (w + 2) }.join("+") + "+"
      io.puts sep
      io.puts "|" + headers.each_with_index.map { |h, i| " " + h.ljust(widths[i]) + " " }.join("|") + "|"
      io.puts sep
      rows.each do |r|
        io.puts "|" + r.each_with_index.map { |c, i| " " + c.ljust(widths[i]) + " " }.join("|") + "|"
      end
      io.puts sep
    end
  end
end
