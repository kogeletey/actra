require "json"

require "./mode"
require "./config"
require "./table"

module Wacli::Render
  module Engine
    def self.render(body_bytes : Bytes, mode : Mode, io : IO, cfg : Config) : Nil
      case mode
      when Mode::Raw
        io.write(body_bytes)
        return
      when Mode::Json, Mode::Table, Mode::Auto
        # continue
      end

      any = parse_json_any(body_bytes)
      if any.nil?
        io.write(body_bytes)
        return
      end

      case mode
      when Mode::Auto
        if any.not_nil!.as_a?
          Table.render(any.not_nil!, io, cfg.table)
        else
          io.puts any.not_nil!.to_pretty_json
        end
      when Mode::Json
        io.puts any.not_nil!.to_pretty_json
      when Mode::Table
        Table.render(any.not_nil!, io, cfg.table)
      else
        io.write(body_bytes)
      end
    end

    private def self.parse_json_any(body_bytes : Bytes) : JSON::Any?
      # Best-effort: if bytes aren't valid UTF-8 JSON, treat as non-JSON.
      s = nil.as(String?)
      begin
        s = String.new(body_bytes)
      rescue
        return nil
      end
      begin
        JSON.parse(s.not_nil!)
      rescue
        nil
      end
    end
  end
end

