require "json"
require "file_utils"
require "time"

require "./xdg"

module Actra
  module Packages
    def self.run(argv : Array(String), stdout : IO, stderr : IO) : Int32
      command = argv[0]?
      case command
      when "install"
        source = argv[1]?
        raise "missing package source" unless source
        data = load
        name = package_name(source)
        data[name] = {
          "source"       => source,
          "installed_at" => Time.utc.to_rfc3339,
        }
        save(data)
        stdout.puts "installed: #{name}"
      when "remove", "uninstall"
        name = argv[1]?
        raise "missing package name" unless name
        data = load
        data.delete(name)
        save(data)
        stdout.puts "removed: #{name}"
      when "update"
        name = argv[1]?
        data = load
        if name
          raise "unknown package: #{name}" unless data.has_key?(name)
          data[name]["updated_at"] = Time.utc.to_rfc3339
          stdout.puts "updated: #{name}"
        else
          data.each_value { |entry| entry["updated_at"] = Time.utc.to_rfc3339 }
          stdout.puts "updated: #{data.size}"
        end
        save(data)
      when "list"
        data = load
        data.each do |name, entry|
          stdout.puts "#{name}\t#{entry["source"]? || ""}"
        end
      when "config"
        stdout.puts db_path
      else
        stderr.puts "usage: actra package <install|remove|update|list|config> ..."
        return 1
      end
      0
    rescue ex
      stderr.puts ex.message
      1
    end

    private def self.load : Hash(String, Hash(String, String))
      path = db_path
      return {} of String => Hash(String, String) unless File.exists?(path)
      any = JSON.parse(File.read(path))
      out = {} of String => Hash(String, String)
      any.as_h.each do |name, entry|
        h = {} of String => String
        entry.as_h.each { |k, v| h[k] = v.to_s }
        out[name] = h
      end
      out
    end

    private def self.save(data : Hash(String, Hash(String, String))) : Nil
      FileUtils.mkdir_p(File.dirname(db_path))
      File.write(db_path, data.to_json)
    end

    private def self.db_path : String
      File.join(Xdg.config_dir, "packages", "installed.json")
    end

    private def self.package_name(source : String) : String
      base = source.split(/[\/:]/).last
      base = base[0, base.size - 4] if base.ends_with?(".git")
      base.empty? ? source.gsub(/[^A-Za-z0-9._-]/, "_") : base
    end
  end
end
