require "db"
require "sqlite3"
require "file_utils"

module Wacli
  class Secrets
    def initialize(@db_path : String)
      FileUtils.mkdir_p(File.dirname(@db_path))
      with_db do |db|
        db.exec <<-SQL
          CREATE TABLE IF NOT EXISTS tokens (
            tool TEXT PRIMARY KEY,
            scheme TEXT NOT NULL,
            token TEXT NOT NULL
          )
        SQL
      end
    end

    def set_bearer(tool : String, token : String) : Nil
      with_db do |db|
        db.exec("INSERT INTO tokens(tool,scheme,token) VALUES(?,?,?) ON CONFLICT(tool) DO UPDATE SET scheme=excluded.scheme, token=excluded.token",
          tool, "bearer", token)
      end
    end

    def get_bearer(tool : String) : String?
      with_db do |db|
        db.query_one?("SELECT token FROM tokens WHERE tool = ? AND scheme = 'bearer' LIMIT 1", tool, as: String)
      end
    end

    private def with_db(&)
      DB.open("sqlite3:#{@db_path}") do |db|
        yield db
      end
    end
  end
end
