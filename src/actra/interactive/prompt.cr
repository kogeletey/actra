require "json"
require "../render/config"

module Actra::Interactive
  class PromptError < Exception
  end

  module Prompt
    def self.ask_string(stdin : IO, stdout : IO, prompt : String, required : Bool) : String
      loop do
        stdout.print "#{prompt}: "
        stdout.flush
        s = stdin.gets
        raise PromptError.new("EOF while reading input") unless s
        v = s.strip
        return v unless required && v.empty?
      end
    end

    def self.ask_bool(stdin : IO, stdout : IO, prompt : String, default : Bool?) : Bool
      suffix =
        case default
        when true  then " [Y/n]"
        when false then " [y/N]"
        else            " [y/n]"
        end
      loop do
        stdout.print "#{prompt}#{suffix}: "
        stdout.flush
        s = stdin.gets
        raise PromptError.new("EOF while reading input") unless s
        v = s.strip.downcase
        if v.empty? && !default.nil?
          return default.not_nil!
        end
        case v
        when "y", "yes", "true", "t", "1" then return true
        when "n", "no", "false", "f", "0" then return false
        else
          next
        end
      end
    end

    def self.ask_enum(stdin : IO, stdout : IO, prompt : String, values : Array(String), cfg : Actra::Render::Config) : String
      if cfg.pickers.prefer_fzf && PickerFzf.available?
        if picked = PickerFzf.pick_one(prompt, values)
          return picked
        end
      end

      stdout.puts prompt
      values.each_with_index do |v, i|
        stdout.puts "  #{i + 1}) #{v}"
      end
      loop do
        stdout.print "Choose (1-#{values.size}): "
        stdout.flush
        s = stdin.gets
        raise PromptError.new("EOF while reading input") unless s
        n = s.strip.to_i?
        next unless n
        next if n < 1 || n > values.size
        return values[n - 1]
      end
    end

    def self.ask_datetime(stdin : IO, stdout : IO, prompt : String, cfg : Actra::Render::Config) : String
      if cfg.pickers.prefer_fzf && PickerFzf.available?
        if picked = PickerFzf.pick_date(prompt, cfg.interactive.datetime.days_ahead)
          time_s = ask_string(stdin, stdout, "Time (HH:MM)", false)
          hh = 0
          mm = 0
          if !time_s.empty?
            parts = time_s.split(":", 2)
            hh = parts[0].to_i
            mm = parts[1]?.try(&.to_i) || 0
          end

          tz = cfg.interactive.datetime.default_timezone.downcase
          tz_choice =
            if tz == "utc"
              ask_enum(stdin, stdout, "Timezone", ["UTC", "Local"], cfg)
            else
              ask_enum(stdin, stdout, "Timezone", ["Local", "UTC"], cfg)
            end

          y, m, d = picked.split("-").map(&.to_i)
          if tz_choice == "UTC"
            t = Time.utc(y, m, d, hh, mm, 0)
            return t.to_s("%Y-%m-%dT%H:%M:%SZ")
          else
            t = Time.local(y, m, d, hh, mm, 0)
            return t.to_s("%Y-%m-%dT%H:%M:%S%:z")
          end
        end
      end

      loop do
        s = ask_string(stdin, stdout, "#{prompt} (RFC3339)", true)
        begin
          Time.parse_rfc3339(s)
          return s
        rescue
          next
        end
      end
    end

    def self.ask_file_path(stdin : IO, stdout : IO, prompt : String, cfg : Actra::Render::Config) : String
      if cfg.pickers.prefer_fzf && PickerFzf.available?
        if picked = PickerFzf.pick_file(prompt)
          return picked
        end
      end
      ask_string(stdin, stdout, prompt, true)
    end

    def self.ask_json(stdin : IO, stdout : IO, prompt : String, required : Bool) : JSON::Any
      loop do
        s = ask_string(stdin, stdout, "#{prompt} (JSON)", required)
        return JSON::Any.new(nil) if s.empty? && !required
        begin
          return JSON.parse(s)
        rescue
          next
        end
      end
    end
  end

  module PickerFzf
    def self.available? : Bool
      !!Process.find_executable("fzf")
    end

    def self.pick_one(prompt : String, options : Array(String)) : String?
      input = IO::Memory.new(options.join("\n") + "\n")
      out_io = IO::Memory.new
      status = Process.run("fzf", picker_args(prompt), input: input, output: out_io, error: Process::Redirect::Close)
      return nil unless status.success?
      s = out_io.to_s.strip
      s.empty? ? nil : s
    rescue
      nil
    end

    def self.pick_many(prompt : String, options : Array(String)) : Array(String)
      input = IO::Memory.new(options.join("\n") + "\n")
      out_io = IO::Memory.new
      status = Process.run("fzf", ["--multi"] + picker_args(prompt), input: input, output: out_io, error: Process::Redirect::Close)
      return [] of String unless status.success?
      out_io.to_s.lines.map(&.strip).reject(&.empty?)
    rescue
      [] of String
    end

    def self.pick_file(prompt : String) : String?
      files = list_files
      return nil if files.empty?
      pick_one(prompt, files)
    end

    def self.pick_files(prompt : String) : Array(String)
      files = list_files
      return [] of String if files.empty?
      pick_many(prompt, files)
    end

    def self.file_context_candidates(prefix : String = "") : Array(String)
      token_prefix = prefix.starts_with?("@") ? prefix[1..] : prefix
      list_files
        .select { |path| token_prefix.empty? || path.starts_with?(token_prefix) || File.basename(path).starts_with?(token_prefix) }
        .map { |path| "@#{normalize_file_path(path)}" }
    end

    def self.context_tokens(paths : Array(String)) : String
      paths.map { |path| shell_sq("@#{normalize_file_path(path)}") }.join(" ")
    end

    def self.pick_date(prompt : String, days_ahead : Int32) : String?
      today = Time.local.to_s("%Y-%m-%d")
      start = Time.parse("%Y-%m-%d", today, Time::Location.local)
      opts = [] of String
      (0..days_ahead).each do |i|
        t = start + i.days
        opts << t.to_s("%Y-%m-%d %a")
      end
      if s = pick_one(prompt, opts)
        s.split(" ", 2)[0]?
      end
    rescue
      nil
    end

    private def self.list_files : Array(String)
      out_io = IO::Memory.new
      status =
        if Process.find_executable("rg")
          Process.run("rg", ["--files"], output: out_io, error: Process::Redirect::Close)
        else
          Process.run("find", [".", "-maxdepth", "6", "-type", "f", "-not", "-path", "./.git/*", "-print"], output: out_io, error: Process::Redirect::Close)
        end
      return [] of String unless status.success?
      out_io.to_s.lines.map { |line| normalize_file_path(line.strip) }.reject(&.empty?)
    rescue
      [] of String
    end

    private def self.normalize_file_path(path : String) : String
      path.starts_with?("./") ? path[2..] : path
    end

    private def self.picker_args(prompt : String) : Array(String)
      ["--height", "30%", "--layout", "reverse", "--border", "top", "--prompt", "#{prompt}> "]
    end

    private def self.shell_sq(s : String) : String
      "'" + s.gsub("'", %q('"'"')) + "'"
    end
  end
end
