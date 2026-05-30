require "json"
require "set"

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
      if cfg.pickers.prefer_tui && PickerTui.available?
        if picked = PickerTui.pick_one(prompt, values)
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
      if cfg.pickers.prefer_tui && PickerTui.available?
        if picked = PickerTui.pick_date(prompt, cfg.interactive.datetime.days_ahead)
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
      if cfg.pickers.prefer_tui && PickerTui.available?
        if picked = PickerTui.pick_file(prompt)
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

  module PickerTui
    enum PickerKey
      Up
      Down
      Select
      Cancel
      Enter
      Unknown
    end

    def self.available? : Bool
      STDIN.tty?
    end

    def self.pick_one(prompt : String, options : Array(String), query : String = "") : String?
      values = filtered_options(options, query)
      return nil if values.empty?
      if forced = test_pick_one(values)
        return forced
      end
      return nil unless STDIN.tty?

      interactive_pick_one(prompt, values)
    end

    def self.pick_many(prompt : String, options : Array(String)) : Array(String)
      values = options
      return [] of String if values.empty?
      if forced = test_pick_many(values)
        return forced
      end
      return [] of String unless STDIN.tty?

      interactive_pick_many(prompt, values)
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
      token_prefix = (prefix.starts_with?("@") ? prefix[1..] : prefix).strip.downcase
      list_file_context_entries
        .select { |entry| file_query_match?(entry.path, token_prefix) }
        .sort { |left, right| compare_file_context_entries(left, right, token_prefix) }
        .map { |entry| "@#{normalize_file_path(entry.path)}" }
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
      picked = pick_one(prompt, opts)
      picked ? picked.split(" ", 2)[0] : nil
    rescue
      nil
    end

    private def self.filtered_options(options : Array(String), query : String) : Array(String)
      return options if query.empty?
      q = query.downcase
      options.select { |option| option.downcase.includes?(q) }
    end

    private def self.interactive_pick_one(prompt : String, options : Array(String)) : String?
      index = 0
      redraw(prompt, options, index)
      begin
        with_raw_terminal do
          loop do
            case read_key
            when PickerKey::Down
              index = (index + 1) % options.size
              redraw(prompt, options, index)
            when PickerKey::Up
              index = (index - 1)
              index += options.size if index < 0
              redraw(prompt, options, index)
            when PickerKey::Select
              return options[index]
            when PickerKey::Enter
              return options[index]
            when PickerKey::Cancel
              return nil
            else
              # no-op
            end
          end
        end
      ensure
        # noop
      end
    end

    private def self.interactive_pick_many(prompt : String, options : Array(String)) : Array(String)
      index = 0
      selected = Set(Int32).new
      redraw_many(prompt, options, index, selected)
      begin
        with_raw_terminal do
          loop do
            case read_key
            when PickerKey::Down
              index = (index + 1) % options.size
              redraw_many(prompt, options, index, selected)
            when PickerKey::Up
              index = (index - 1)
              index += options.size if index < 0
              redraw_many(prompt, options, index, selected)
            when PickerKey::Select
              selected.add(index)
              redraw_many(prompt, options, index, selected)
            when PickerKey::Enter
              return selected.to_a.empty? ? [options[index]] : selected.to_a.sort!.map { |item| options[item] }
            when PickerKey::Cancel
              return [] of String
            end
          end
        end
      ensure
        # fallback noop
      end
    end

    private def self.redraw(prompt : String, options : Array(String), index : Int32)
      STDOUT.print "\e7"
      STDOUT.print "\r"
      STDOUT.print "\e[1E"
      STDOUT.print "\r"
      STDOUT.print "\e[0J"
      STDOUT.puts "#{prompt}>"
      options.each_with_index do |option, item_index|
        marker = item_index == index ? ">" : " "
        STDOUT.puts "#{marker} #{item_index + 1}) #{option}"
      end
      STDOUT.flush
      STDOUT.print "\e8"
      options[index]?
    end

    private def self.redraw_many(prompt : String, options : Array(String), index : Int32, selected : Set(Int32))
      STDOUT.print "\e7"
      STDOUT.print "\r"
      STDOUT.print "\e[1E"
      STDOUT.print "\r"
      STDOUT.print "\e[0J"
      STDOUT.puts "#{prompt}> (space to toggle, Enter to finish)"
      options.each_with_index do |option, item_index|
        marker = item_index == index ? ">" : " "
        check = selected.includes?(item_index) ? "[x]" : "[ ]"
        STDOUT.puts "#{marker} #{item_index + 1}) #{check} #{option}"
      end
      STDOUT.flush
      STDOUT.print "\e8"
    end

    private def self.test_pick_one(options : Array(String)) : String?
      action = ENV["ACTRA_TEST_PICKER_ACTION"]? || ENV["ACTRA_TEST_FZF_ACTION"]?
      if action
        picked = match_option(options, action)
        return picked if picked
      end

      if selection = ENV["ACTRA_TEST_PICKER_SELECTION"]? || ENV["ACTRA_TEST_FZF_SELECTION"]?
        candidate = selection.lines.first?.try(&.strip) || ""
        return nil if candidate.empty?
        return match_option(options, candidate)
      end
      nil
    end

    private def self.test_pick_many(options : Array(String)) : Array(String)
      action = ENV["ACTRA_TEST_PICKER_ACTION"]? || ENV["ACTRA_TEST_FZF_ACTION"]?
      if action
        picked = match_option(options, action)
        return picked ? [picked] : [] of String
      end

      if selection = ENV["ACTRA_TEST_PICKER_SELECTION"]? || ENV["ACTRA_TEST_FZF_SELECTION"]?
        selected = selection.lines.map(&.strip).reject(&.empty?).map { |entry| match_option(options, entry) }
        return selected.compact
      end

      [] of String
    end

    private def self.match_option(options : Array(String), raw : String) : String?
      normalized = raw.strip
      return nil if normalized.empty?
      exact = options.find { |option| option == normalized }
      return exact if exact
      lower = normalized.downcase
      options.find { |option| option.downcase == lower } || options.find { |option| option.downcase.includes?(lower) }
    end

    private def self.list_files : Array(String)
      out_io = IO::Memory.new
      status =
        if Process.find_executable("rg")
          Process.run("rg", ["--files"], output: out_io, error: Process::Redirect::Close)
        else
          Process.run("find", [".", "-maxdepth", "8", "-type", "f", "-not", "-path", "./.git/*", "-print"], output: out_io, error: Process::Redirect::Close)
        end
      return [] of String unless status.success?
      out_io.to_s.lines.map { |line| normalize_file_path(line.strip) }.reject(&.empty?)
    rescue
      [] of String
    end

    private struct FileContextEntry
      getter path : String
      getter directory : Bool

      def initialize(@path : String, @directory : Bool)
      end
    end

    private def self.list_file_context_entries : Array(FileContextEntry)
      entries = {} of String => FileContextEntry

      list_files.each do |path|
        normalized = normalize_file_path(path)
        entries[normalized] = FileContextEntry.new(normalized, false)
        each_parent_path(normalized) do |dir|
          entries[dir] ||= FileContextEntry.new(dir, true)
        end
      end

      list_directories.each do |path|
        normalized = normalize_file_path(path)
        next if normalized.empty? || normalized == "."
        entries[normalized] ||= FileContextEntry.new(normalized, true)
      end

      entries.values
    end

    private def self.list_directories : Array(String)
      return [] of String unless Process.find_executable("find")

      out_io = IO::Memory.new
      status = Process.run("find", [".", "-maxdepth", "8", "-type", "d", "-not", "-path", "./.git", "-not", "-path", "./.git/*", "-print"], output: out_io, error: Process::Redirect::Close)
      return [] of String unless status.success?
      out_io.to_s.lines.map { |line| normalize_file_path(line.strip) }.reject(&.empty?)
    rescue
      [] of String
    end

    private def self.each_parent_path(path : String, &)
      dir = File.dirname(path)
      until dir == "." || dir == "/" || dir.empty?
        yield dir
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
    end

    private def self.compare_file_context_entries(left : FileContextEntry, right : FileContextEntry, query : String) : Int32
      left_score = file_query_score(left.path, query)
      right_score = file_query_score(right.path, query)
      return left_score <=> right_score unless left_score == right_score

      left_type = left.directory ? 0 : 1
      right_type = right.directory ? 0 : 1
      return left_type <=> right_type unless left_type == right_type

      left.path.downcase <=> right.path.downcase
    end

    private def self.file_query_score(path : String, query : String) : Int32
      return 0 if query.empty?

      normalized = normalize_file_path(path).downcase
      basename = File.basename(normalized)
      return 0 if normalized == query || basename == query
      return 1 if normalized.starts_with?(query)
      return 2 if basename.starts_with?(query)
      return 3 if normalized.includes?(query) || basename.includes?(query)
      4
    end

    private def self.file_query_match?(path : String, query : String) : Bool
      return true if query.empty?

      normalized = normalize_file_path(path).downcase
      basename = File.basename(normalized)
      tokens = query.split(/\s+/).reject(&.empty?)
      tokens.all? do |token|
        normalized.includes?(token) || basename.includes?(token) || fuzzy_match?(normalized, token)
      end
    end

    private def self.fuzzy_match?(value : String, query : String) : Bool
      offset = 0
      query.each_char do |char|
        found = value.index(char, offset)
        return false unless found
        offset = found + 1
      end
      true
    end

    private def self.normalize_file_path(path : String) : String
      path.starts_with?("./") ? path[2..] : path
    end

    private def self.with_raw_terminal(&)
      state = IO::Memory.new
      status = begin
        Process.run("stty", ["-g"], output: state, error: Process::Redirect::Close)
      rescue
        nil
      end

      if status.nil? || !status.success?
        return yield
      end

      saved = state.to_s.strip
      if saved.empty?
        return yield
      end

      begin
        Process.run("stty", ["-icanon", "-echo"], error: Process::Redirect::Close)
        Process.run("stty", ["-isig", "-ixon"], error: Process::Redirect::Close)
        yield
      ensure
        Process.run("stty", [saved], error: Process::Redirect::Close) if !saved.empty?
      end
    end

    private def self.read_key : PickerKey
      key = STDIN.read_byte
      return PickerKey::Cancel if key.nil?

      case key
      when 10, 13
        return PickerKey::Enter
      when 27
        second = STDIN.read_byte
        return PickerKey::Cancel if second.nil?
        return PickerKey::Cancel if second != 91

        third = STDIN.read_byte
        return PickerKey::Cancel if third.nil?
        return case third
        when 65     then PickerKey::Up
        when 66     then PickerKey::Down
        when 67, 68 then PickerKey::Unknown
        else
          PickerKey::Unknown
        end
      when 106
        PickerKey::Down
      when 107
        PickerKey::Up
      when 32
        PickerKey::Select
      when 3
        PickerKey::Cancel
      when 113
        PickerKey::Cancel
      when 4
        PickerKey::Cancel
      else
        PickerKey::Unknown
      end
    end

    private def self.shell_sq(s : String) : String
      "'" + s.gsub("'", %q('"'"')) + "'"
    end
  end

  # Compatibility alias for older config references and tests that still import PickerFzf.
  alias PickerFzf = PickerTui
end
