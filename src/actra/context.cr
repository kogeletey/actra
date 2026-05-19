require "file_utils"

require "./xdg"

module Actra
  struct AgentContext
    getter system_prompt : String?
    getter prompt : String

    def initialize(@system_prompt : String?, @prompt : String)
    end
  end

  module Context
    CONTEXT_FILES = {"AGENTS.md", "CLAUDE.md"}

    def self.build(args : Array(String), stdin : IO, load_context_files : Bool, explicit_system : String?, append_system : String?, prompt_templates : Array(String) = [] of String, skills : Array(String) = [] of String) : AgentContext
      prompt_parts = [] of String
      prompt_templates.each do |path|
        prompt_parts << read_resource(path, "Prompt template")
      end
      args.each do |arg|
        if arg.starts_with?("@") && arg.size > 1 && File.file?(arg[1..])
          path = arg[1..]
          prompt_parts << "File: #{path}\n\n#{File.read(path)}"
        else
          prompt_parts << arg
        end
      end

      unless stdin.tty?
        piped = stdin.gets_to_end.strip
        prompt_parts << piped unless piped.empty?
      end

      system_parts = [] of String
      if explicit_system
        system_parts << explicit_system.not_nil!
      elsif load_context_files
        system_parts.concat(load_system_files)
      end
      skills.each do |path|
        system_parts << read_resource(path, "Skill")
      end
      system_parts << append_system.not_nil! if append_system

      AgentContext.new(system_parts.empty? ? nil : system_parts.join("\n\n"), prompt_parts.join(" ").strip)
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
