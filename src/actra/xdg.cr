module Actra
  module Xdg
    def self.home : String
      ENV["HOME"]? || raise "HOME is not set"
    end

    def self.test_root : String?
      ENV["ACTRA_TEST_ROOT"]?
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
      File.join(config_home, "actra")
    end

    def self.legacy_astra_config_dir : String
      File.join(config_home, "astra")
    end

    def self.tools_dir : String
      File.join(config_dir, "tools")
    end

    def self.cache_dir : String
      File.join(cache_home, "actra")
    end

    def self.config_path : String
      File.join(config_dir, "config.rcl")
    end

    def self.legacy_astra_config_path : String
      File.join(legacy_astra_config_dir, "config.rcl")
    end

    def self.config_load_path : String
      File.exists?(config_path) || !File.exists?(legacy_astra_config_path) ? config_path : legacy_astra_config_path
    end

    def self.config_write_path : String
      config_path
    end

    def self.lock_path : String
      File.join(config_dir, "actra.lock")
    end
  end
end
