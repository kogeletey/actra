require "file_utils"

require "./prompt_preset"
require "./xdg"

module Actra
  struct AgentContext
    getter system_prompt : String?
    getter prompt : String
    getter estimated_prompt_tokens : Int32

    def initialize(@system_prompt : String?, @prompt : String, @estimated_prompt_tokens : Int32)
    end
  end

  module Context
    CONTEXT_FILES = {"AGENTS.md", "CLAUDE.md"}
    MAX_CONTEXT_FILE_BYTES      = 64 * 1024
    MAX_DIRECTORY_CONTEXT_FILES = 40
    SKIPPED_DIRECTORIES         = {".git", ".hg", ".svn", ".shards", "lib", "node_modules"}

    def self.build(args : Array(String), stdin : IO, load_context_files : Bool, explicit_system : String?, append_system : String?, prompt_templates : Array(String) = [] of String, skills : Array(String) = [] of String, prompt_modes : Array(String) = [] of String) : AgentContext
      prompt_parts = [] of String
      prompt_templates.each do |path|
        prompt_parts << read_resource(path, "Prompt template")
      end
      args.each do |arg|
        if arg.starts_with?("@") && arg.size > 1
          path = arg[1..]
          if File.file?(path)
            prompt_parts << read_context_file(path)
          elsif File.directory?(path)
            prompt_parts << read_context_directory(path)
          else
            prompt_parts << arg
          end
        else
          prompt_parts << arg
        end
      end

      unless stdin.tty?
        piped = stdin.gets_to_end.strip
        prompt_parts << piped unless piped.empty?
      end

      system_parts = [] of String
      if prompt_modes.empty? && explicit_system.nil?
        system_parts << PromptPreset.system_prompt("code")
      else
        prompt_modes.each { |mode| system_parts << PromptPreset.system_prompt(mode) }
      end

      if explicit_system
        system_parts << explicit_system.not_nil!
      elsif load_context_files
        system_parts.concat(load_system_files)
      end
      skills.each do |path|
        system_parts << read_resource(path, "Skill")
      end
      system_parts << append_system.not_nil! if append_system

      prompt = prompt_parts.join(" ").strip
      AgentContext.new(system_parts.empty? ? nil : system_parts.join("\n\n"), prompt, estimate_tokens(prompt))
    end

    def self.estimate_tokens(text : String) : Int32
      return 0 if text.empty?

      (text.bytesize + 3) // 4
    end

    private def self.read_context_file(path : String) : String
      content = read_text(path)
      String.build do |io|
        io.puts "File: #{path}"
        io.puts "Approx tokens: #{estimate_tokens(content)}"
        io.puts
        io << content
      end
    end

    private def self.read_context_directory(path : String) : String
      root = File.expand_path(path)
      files = Dir.glob(File.join(root, "**", "*"))
        .select { |candidate| File.file?(candidate) }
        .reject { |candidate| skipped_context_path?(root, candidate) }
        .sort
        .first(MAX_DIRECTORY_CONTEXT_FILES)

      sections = files.map do |file|
        relative = relative_path(root, file)
        content = read_text(file)
        "--- #{relative} ---\n#{content}"
      rescue
        nil
      end.compact

      body = sections.join("\n\n")
      String.build do |io|
        io.puts "Directory: #{path}"
        io.puts "Files included: #{sections.size}"
        io.puts "Approx tokens: #{estimate_tokens(body)}"
        io.puts
        io << body
      end
    end

    private def self.read_text(path : String) : String
      content = File.read(path)
      raise "binary context file: #{path}" if content.includes?('\0')
      return content if content.bytesize <= MAX_CONTEXT_FILE_BYTES

      content.byte_slice(0, MAX_CONTEXT_FILE_BYTES) + "\n[truncated]"
    end

    private def self.skipped_context_path?(root : String, path : String) : Bool
      relative_path(root, path).split(File::SEPARATOR).any? { |part| SKIPPED_DIRECTORIES.includes?(part) }
    end

    private def self.relative_path(root : String, path : String) : String
      prefix = root.ends_with?(File::SEPARATOR) ? root : root + File::SEPARATOR
      path.starts_with?(prefix) ? path[prefix.size..] : path
    end

    private def self.read_resource(path : String, label : String) : String
      expanded = path.starts_with?("~") ? path.sub("~", Xdg.home) : path
      if File.directory?(expanded)
        entry = File.join(expanded, "SKILL.md")
        entry = File.join(expanded, "README.md") unless File.file?(entry)
        expanded = entry
      end
      raise "#{label} not found: #{path}" unless File.file?(expanded)
      "#{label}: #{expanded}\n\n#{File.read(expanded)}"
    end

    private def self.load_system_files : Array(String)
      parts = [] of String

      global_agent = File.join(Xdg.config_dir, "AGENTS.md")
      parts << File.read(global_agent) if File.file?(global_agent)
      global_system = File.join(Xdg.config_dir, "SYSTEM.md")
      parts << File.read(global_system) if File.file?(global_system)

      each_parent_dir(Dir.current) do |dir|
        CONTEXT_FILES.each do |name|
          path = File.join(dir, name)
          parts << File.read(path) if File.file?(path)
        end
      end

      local_system = File.join(Dir.current, ".actra", "SYSTEM.md")
      parts << File.read(local_system) if File.file?(local_system)
      global_append = File.join(Xdg.config_dir, "APPEND_SYSTEM.md")
      parts << File.read(global_append) if File.file?(global_append)
      local_append = File.join(Dir.current, ".actra", "APPEND_SYSTEM.md")
      parts << File.read(local_append) if File.file?(local_append)

      parts
    end

    private def self.each_parent_dir(start : String, &block : String ->)
      dirs = [] of String
      current = File.expand_path(start)
      loop do
        dirs << current
        parent = File.dirname(current)
        break if parent == current
        current = parent
      end
      dirs.reverse_each { |dir| yield dir }
    end
  end
end
