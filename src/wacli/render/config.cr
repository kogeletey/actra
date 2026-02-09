require "./mode"

module Wacli::Render
  struct TableConfig
    getter max_rows : Int32
    getter max_columns : Int32
    getter max_cell_width : Int32

    def initialize(@max_rows : Int32, @max_columns : Int32, @max_cell_width : Int32)
    end

    def self.default : TableConfig
      new(200, 10, 80)
    end
  end

  struct PickersConfig
    getter prefer_fzf : Bool
    def initialize(@prefer_fzf : Bool); end
    def self.default : PickersConfig
      new(true)
    end
  end

  struct DateTimeConfig
    getter days_ahead : Int32
    getter default_timezone : String # "local" | "utc"
    def initialize(@days_ahead : Int32, @default_timezone : String); end
    def self.default : DateTimeConfig
      new(365, "local")
    end
  end

  struct InteractiveConfig
    getter enabled : Bool
    getter datetime : DateTimeConfig

    def initialize(@enabled : Bool, @datetime : DateTimeConfig)
    end

    def self.default : InteractiveConfig
      new(true, DateTimeConfig.default)
    end
  end

  enum FieldKind
    String
    Boolean
    Enum
    DateTime
    File
  end

  struct FieldRule
    getter pointer : String
    getter kind : FieldKind
    getter prompt : String
    getter required : Bool
    getter enum_values : Array(String)
    getter default_bool : Bool?

    def initialize(
      @pointer : String,
      @kind : FieldKind,
      @prompt : String,
      @required : Bool = false,
      @enum_values : Array(String) = [] of String,
      @default_bool : Bool? = nil
    )
    end
  end

  struct OperationRule
    getter body_type : String # v0.2: only "object" is supported
    getter fields : Array(FieldRule)

    def initialize(@body_type : String, @fields : Array(FieldRule))
    end
  end

  struct Config
    getter default_mode : Mode
    getter table : TableConfig
    getter pickers : PickersConfig
    getter interactive : InteractiveConfig
    getter operations : Hash(String, OperationRule)

    def initialize(
      @default_mode : Mode,
      @table : TableConfig,
      @pickers : PickersConfig,
      @interactive : InteractiveConfig,
      @operations : Hash(String, OperationRule)
    )
    end

    def self.default : Config
      new(Mode::Auto, TableConfig.default, PickersConfig.default, InteractiveConfig.default, {} of String => OperationRule)
    end
  end
end

