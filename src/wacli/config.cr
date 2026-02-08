require "json"

require "./xdg"

module Wacli
  struct Config
    getter db_path : String
    getter install_dir : String
    getter uri_schemes : Hash(String, String)

    def initialize(@db_path : String, @install_dir : String, @uri_schemes : Hash(String, String))
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
        new(db_path, install_dir, uri_schemes)
      else
        new(default_db_path, default_install_dir, {"registry" => "https://wacli.ofs.lol"})
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
  end
end
