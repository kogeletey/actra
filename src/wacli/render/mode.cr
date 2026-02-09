module Wacli::Render
  enum Mode
    Auto
    Table
    Json
    Raw

    def self.parse(s : String?) : Mode?
      return nil unless s
      case s.downcase
      when "auto"  then Mode::Auto
      when "table" then Mode::Table
      when "json"  then Mode::Json
      when "raw"   then Mode::Raw
      else
        nil
      end
    end
  end
end

