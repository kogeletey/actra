require "json"

module Wacli::Wasm
  struct Config
    getter db_path : String

    def initialize(@db_path : String)
    end

    def self.load(path : String) : Config
      any = JSON.parse(File.read(path))
      db_path = any["dbPath"]?.try(&.as_s?) || raise "missing config key: dbPath"
      Config.new(db_path)
    end
  end
end

