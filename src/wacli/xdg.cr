module Wacli
  module Xdg
    def self.home : String
      ENV["HOME"]? || raise "HOME is not set"
    end

    def self.test_root : String?
      ENV["WACLI_TEST_ROOT"]?
    end

    def self.config_home : String
      if root = test_root
        File.join(root, "config")
      else
        ENV["XDG_CONFIG_HOME"]? || File.join(home, ".config")
      end
    end

    def self.cache_home : String
      if root = test_root
        File.join(root, "cache")
      else
        ENV["XDG_CACHE_HOME"]? || File.join(home, ".cache")
      end
    end

    def self.config_dir : String
      File.join(config_home, "wacli")
    end

    def self.tools_dir : String
      File.join(config_dir, "tools")
    end

    def self.cache_dir : String
      File.join(cache_home, "wacli")
    end

    def self.config_path : String
      File.join(config_dir, "wacfg.json")
    end

    def self.lock_path : String
      File.join(config_dir, "wa.lock")
    end
  end
end
