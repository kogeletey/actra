require "json"

require "./xdg"
require "./render/config"

module Wacli
  struct Config
    getter db_path : String
    getter install_dir : String
    getter uri_schemes : Hash(String, String)
    getter render : Render::Config

    def initialize(@db_path : String, @install_dir : String, @uri_schemes : Hash(String, String), @render : Render::Config)
    end

    def self.load : Config
      path = Xdg.config_path
      if File.exists?(path)
        any = JSON.parse(File.read(path))
        db_path = expand_home(any["db_path"]?.try(&.as_s?) || default_db_path)
        install_dir = expand_home(any["install_dir"]?.try(&.as_s?) || default_install_dir)
        uri_schemes = {} of String => String
        if h = any["uri_schemes"]?.try(&.as_h?)
          h.each { |k, v| uri_schemes[k] = v.as_s }
        end
        render = parse_render(any["render"]?)
        new(db_path, install_dir, uri_schemes, render)
      else
        new(default_db_path, default_install_dir, {"registry" => "https://wacli.ofs.lol"}, Render::Config.default)
      end
    end

    private def self.default_db_path : String
      File.join(Xdg.cache_home, "wacrd.db")
    end

    private def self.default_install_dir : String
      File.join(Xdg.home, ".local", "bin")
    end

    private def self.expand_home(s : String) : String
      if s.includes?("$HOME")
        s.gsub("$HOME", Xdg.home)
      else
        s
      end
    end

    private def self.parse_render(any : JSON::Any?) : Render::Config
      return Render::Config.default unless any
      h = any.as_h?
      return Render::Config.default unless h

      default_mode = Render::Mode.parse(h["default_mode"]?.try(&.as_s?)) || Render::Mode::Auto

      table = Render::TableConfig.default
      if th = h["table"]?.try(&.as_h?)
        max_rows = th["max_rows"]?.try(&.as_i?) || table.max_rows
        max_columns = th["max_columns"]?.try(&.as_i?) || table.max_columns
        max_cell_width = th["max_cell_width"]?.try(&.as_i?) || table.max_cell_width
        table = Render::TableConfig.new(max_rows.to_i, max_columns.to_i, max_cell_width.to_i)
      end

      pickers = Render::PickersConfig.default
      if ph = h["pickers"]?.try(&.as_h?)
        prefer_fzf = ph["prefer_fzf"]?.try(&.as_bool?) || pickers.prefer_fzf
        pickers = Render::PickersConfig.new(prefer_fzf)
      end

      interactive = Render::InteractiveConfig.default
      if ih = h["interactive"]?.try(&.as_h?)
        enabled = ih["enabled"]?.try(&.as_bool?) || interactive.enabled
        dt = Render::DateTimeConfig.default
        if dth = ih["datetime"]?.try(&.as_h?)
          days_ahead = dth["days_ahead"]?.try(&.as_i?) || dt.days_ahead
          tz = dth["default_timezone"]?.try(&.as_s?) || dt.default_timezone
          dt = Render::DateTimeConfig.new(days_ahead.to_i, tz)
        end
        interactive = Render::InteractiveConfig.new(enabled, dt)
      end

      ops = {} of String => Render::OperationRule
      if oh = h["operations"]?.try(&.as_h?)
        oh.each do |op_key, op_any|
          next unless oph = op_any.as_h?
          next unless bh = oph["body"]?.try(&.as_h?)
          body_type = bh["type"]?.try(&.as_s?) || "object"
          fields = [] of Render::FieldRule
          if fa = bh["fields"]?.try(&.as_a?)
            fa.each do |f_any|
              next unless fh = f_any.as_h?
              pointer = fh["pointer"]?.try(&.as_s?) || next
              kind_s = fh["kind"]?.try(&.as_s?) || "string"
              prompt = fh["prompt"]?.try(&.as_s?) || pointer
              required = fh["required"]?.try(&.as_bool?) || false

              kind =
                case kind_s.downcase
                when "string"   then Render::FieldKind::String
                when "boolean"  then Render::FieldKind::Boolean
                when "enum"     then Render::FieldKind::Enum
                when "datetime" then Render::FieldKind::DateTime
                when "file"     then Render::FieldKind::File
                else                 Render::FieldKind::String
                end

              enum_values = [] of String
              if kind == Render::FieldKind::Enum
                if eva = fh["values"]?.try(&.as_a?)
                  enum_values = eva.compact_map(&.as_s?)
                end
              end

              default_bool = nil.as(Bool?)
              if kind == Render::FieldKind::Boolean
                default_bool = fh["default"]?.try(&.as_bool?)
              end

              fields << Render::FieldRule.new(pointer, kind, prompt, required, enum_values, default_bool)
            end
          end
          ops[op_key] = Render::OperationRule.new(body_type, fields)
        end
      end

      Render::Config.new(default_mode, table, pickers, interactive, ops)
    rescue
      Render::Config.default
    end
  end
end
