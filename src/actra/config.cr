require "json"

require "./xdg"
require "./rcl"
require "./permission"
require "./render/config"

module Actra
  struct HttpSignatureConfig
    getter key_id : String
    getter private_key_path : String
    getter algorithm : String

    def initialize(@key_id : String, @private_key_path : String, @algorithm : String)
    end
  end

  struct ActorConfig
    getter name : String
    getter command : String
    getter inbox : String
    getter outbox : String
    getter work_type : String

    def initialize(@name : String, @command : String, @inbox : String, @outbox : String, @work_type : String)
    end
  end

  struct ServerConfig
    getter name : String
    getter base_url : String
    getter actor_id : String
    getter inbox : String
    getter outbox : String
    getter http_signature : HttpSignatureConfig?
    getter actors : Array(ActorConfig)

    def initialize(@name : String, @base_url : String, @actor_id : String, @inbox : String, @outbox : String, @http_signature : HttpSignatureConfig?, @actors : Array(ActorConfig))
    end

    def actor_for_command(command : String) : ActorConfig?
      actors.find { |actor| actor.command == command || "@#{actor.name}" == command }
    end
  end

  struct AiModelConfig
    getter name : String
    getter reasoning_effort : String?

    def initialize(@name : String, @reasoning_effort : String? = nil)
    end
  end

  struct AiProviderConfig
    getter name : String
    getter api : String
    getter base_url : String
    getter api_key : String?
    getter auth_header : Bool
    getter headers : Hash(String, String)
    getter default_model : String?
    getter models : Hash(String, AiModelConfig)
    getter forgefed_server : String?
    getter forgefed_actor : String?

    def initialize(
      @name : String,
      @api : String,
      @base_url : String,
      @api_key : String?,
      @auth_header : Bool,
      @headers : Hash(String, String),
      @default_model : String?,
      @models : Hash(String, AiModelConfig),
      @forgefed_server : String? = nil,
      @forgefed_actor : String? = nil,
    )
    end
  end

  struct ExtensionConfig
    getter name : String
    getter command : String
    getter events : Array(String)

    def initialize(@name : String, @command : String, @events : Array(String))
    end

    def handles?(event : String) : Bool
      events.empty? || events.includes?(event)
    end
  end

  struct FileEditorConfig
    getter name : String
    getter patterns : Array(String)
    getter extensions : Array(String)
    getter editor : String

    def initialize(@name : String, @patterns : Array(String), @extensions : Array(String), @editor : String)
    end

    def matches?(path : String) : Bool
      normalized_exts = extensions.map { |ext| ext.starts_with?(".") ? ext.downcase : ".#{ext.downcase}" }
      path_ext = File.extname(path).downcase
      return true if !path_ext.empty? && normalized_exts.includes?(path_ext)

      basename = File.basename(path)
      patterns.any? do |pattern|
        File.match?(pattern, path) || File.match?(pattern, basename)
      end
    end
  end

  struct AtMenuActionConfig
    getter name : String
    getter label : String
    getter kind : String
    getter org_todo_path : String?
    getter category : String?
    getter executor : String?
    getter provider : String?
    getter model : String?
    getter prompt_modes : Array(String)

    def initialize(@name : String, @label : String, @kind : String, @org_todo_path : String? = nil, @category : String? = nil, @executor : String? = nil, @provider : String? = nil, @model : String? = nil, @prompt_modes : Array(String) = [] of String)
    end
  end

  struct AtConfig
    getter menu_actions : Array(AtMenuActionConfig)

    def initialize(@menu_actions : Array(AtMenuActionConfig) = [] of AtMenuActionConfig)
    end
  end

  struct Config
    DEFAULT_MODEL = "@auto@lefine.pro"

    getter db_path : String
    getter install_dir : String
    getter uri_schemes : Hash(String, String)
    getter render : Render::Config
    getter default_server : String
    getter servers : Hash(String, ServerConfig)
    getter default_provider : String
    getter default_model : String?
    getter session_dir : String
    getter providers : Hash(String, AiProviderConfig)
    getter extensions : Array(ExtensionConfig)
    getter file_editors : Array(FileEditorConfig)
    getter at : AtConfig
    getter permissions : PermissionsConfig

    def initialize(
      @db_path : String,
      @install_dir : String,
      @uri_schemes : Hash(String, String),
      @render : Render::Config,
      @default_server : String = "lefine.pro",
      @servers : Hash(String, ServerConfig) = {} of String => ServerConfig,
      @default_provider : String = "openai",
      @default_model : String? = nil,
      @session_dir : String = Config.default_session_dir,
      @providers : Hash(String, AiProviderConfig) = Config.default_providers,
      @extensions : Array(ExtensionConfig) = [] of ExtensionConfig,
      @file_editors : Array(FileEditorConfig) = [] of FileEditorConfig,
      @at : AtConfig = AtConfig.new,
      @permissions : PermissionsConfig = PermissionsConfig.default,
    )
    end

    def self.load : Config
      path = Xdg.config_load_path
      if File.exists?(path)
        raw = File.read(path)
        raw.lstrip.starts_with?("{") ? load_json(raw) : load_rcl(raw)
      else
        legacy_path = File.join(Xdg.config_home, "actra", "actra.json")
        if File.exists?(legacy_path)
          load_json(File.read(legacy_path))
        else
          default
        end
      end
    end

    def self.default : Config
      new(default_db_path, default_install_dir, {"registry" => "https://actra.ofs.lol"}, Render::Config.default, "lefine.pro", {} of String => ServerConfig, "openai", nil, default_session_dir, default_providers, [] of ExtensionConfig, [] of FileEditorConfig, default_at_config)
    end

    def self.load_rcl(raw : String) : Config
      doc = Rcl.parse(raw)
      base = doc.first_block("base")

      db_path = expand_home(string_property(base, "db_path") || default_db_path)
      install_dir = expand_home(string_property(base, "install_dir") || default_install_dir)
      default_server = string_property(base, "default_server") || "lefine.pro"
      default_provider = string_property(base, "default_provider") || "openai"
      default_model = string_property(base, "default_model")
      session_dir = expand_home(string_property(base, "session_dir") || default_session_dir)

      uri_schemes = {"registry" => "https://actra.ofs.lol"}
      if schemes = doc.first_block("uri_schemes")
        schemes.properties.each do |key, value|
          uri_schemes[key] = value.to_s
        end
      end

      servers = {} of String => ServerConfig
      doc.blocks_named("server").each do |block|
        name = block.argument || raise Rcl::Error.new("server block requires a name")
        server = parse_server(name, block)
        servers[name] = server
      end

      providers = default_providers
      doc.blocks_named("provider").each do |block|
        name = block.argument || raise Rcl::Error.new("provider block requires a name")
        providers[name] = parse_provider(name, block)
      end

      extensions = [] of ExtensionConfig
      doc.blocks_named("extension").each do |block|
        name = block.argument || raise Rcl::Error.new("extension block requires a name")
        extensions << parse_extension(name, block)
      end

      file_editors = [] of FileEditorConfig
      doc.blocks_named("filetype").each do |block|
        file_editors << parse_file_editor(block)
      end

      at = parse_at(doc.first_block("at"))
      permissions = parse_permissions(doc.first_block("permissions"))

      new(db_path, install_dir, uri_schemes, Render::Config.default, default_server, servers, default_provider, default_model, session_dir, providers, extensions, file_editors, at, permissions)
    end

    def self.load_json(raw : String) : Config
      any = JSON.parse(raw)
      db_path = expand_home(any["db_path"]?.try(&.as_s?) || default_db_path)
      install_dir = expand_home(any["install_dir"]?.try(&.as_s?) || default_install_dir)
      uri_schemes = {"registry" => "https://actra.ofs.lol"}
      if h = any["uri_schemes"]?.try(&.as_h?)
        h.each { |k, v| uri_schemes[k] = v.as_s }
      end
      default_provider = any["default_provider"]?.try(&.as_s?) || "openai"
      default_model = any["default_model"]?.try(&.as_s?)
      session_dir = expand_home(any["session_dir"]?.try(&.as_s?) || default_session_dir)
      file_editors = [] of FileEditorConfig
      if fa = any["filetypes"]?.try(&.as_a?)
        fa.each do |item|
          next unless h = item.as_h?
          name = h["name"]?.try(&.as_s?) || "filetype"
          editor = h["editor"]?.try(&.as_s?) || h["command"]?.try(&.as_s?) || next
          patterns = h["patterns"]?.try(&.as_a?).try { |a| a.compact_map(&.as_s?) } || [] of String
          extensions = h["extensions"]?.try(&.as_a?).try { |a| a.compact_map(&.as_s?) } || [] of String
          file_editors << FileEditorConfig.new(name, patterns, extensions, editor)
        end
      end
      at = default_at_config
      if ah = any["at"]?.try(&.as_h?)
        actions = [] of AtMenuActionConfig
        if aa = ah["actions"]?.try(&.as_a?)
          aa.each do |item|
            next unless h = item.as_h?
            name = h["name"]?.try(&.as_s?) || "action"
            kind = h["kind"]?.try(&.as_s?) || "org_todo"
            label = h["label"]?.try(&.as_s?) || name
            path = h["org_todo_path"]?.try(&.as_s?).try { |p| expand_home(p) }
            category = h["category"]?.try(&.as_s?)
            executor = h["executor"]?.try(&.as_s?) || h["assignee"]?.try(&.as_s?)
            actions << AtMenuActionConfig.new(name, label, kind, path, category, executor, h["provider"]?.try(&.as_s?), h["model"]?.try(&.as_s?), h["prompt_modes"]?.try(&.as_a?).try { |a| a.compact_map(&.as_s?) } || [] of String)
          end
        end
        at = AtConfig.new(actions.empty? ? at.menu_actions : actions)
      end
      permissions = parse_permissions_json(any["permissions"]?)
      new(db_path, install_dir, uri_schemes, parse_render(any["render"]?), "lefine.pro", {} of String => ServerConfig, default_provider, default_model, session_dir, default_providers, [] of ExtensionConfig, file_editors, at, permissions)
    end

    def server(name : String? = nil) : ServerConfig?
      servers[name || default_server]?
    end

    def actor_for_command(command : String) : Tuple(ServerConfig, ActorConfig)?
      servers.each_value do |server|
        if actor = server.actor_for_command(command)
          return {server, actor}
        end
      end
      nil
    end

    def provider(name : String? = nil) : AiProviderConfig?
      providers[name || default_provider]?
    end

    def editor_for_file(path : String) : String?
      file_editors.find(&.matches?(path)).try(&.editor)
    end

    private def self.default_db_path : String
      File.join(Xdg.cache_home, "actra.db")
    end

    private def self.default_install_dir : String
      File.join(Xdg.home, ".local", "bin")
    end

    def self.default_session_dir : String
      File.join(Xdg.cache_dir, "sessions")
    end

    def self.default_at_config : AtConfig
      AtConfig.new
    end

    def self.default_providers : Hash(String, AiProviderConfig)
      {
        "openai" => AiProviderConfig.new(
          "openai",
          "openai-responses",
          "https://api.openai.com/v1",
          "OPENAI_API_KEY",
          true,
          {} of String => String,
          nil,
          {} of String => AiModelConfig
        ),
        "ollama" => AiProviderConfig.new(
          "ollama",
          "openai-chat",
          "http://127.0.0.1:11434/v1",
          nil,
          false,
          {} of String => String,
          "llama3.1:8b",
          {} of String => AiModelConfig
        ),
        "llama.cpp" => AiProviderConfig.new(
          "llama.cpp",
          "openai-chat",
          "http://127.0.0.1:8080/v1",
          nil,
          false,
          {} of String => String,
          "local",
          {} of String => AiModelConfig
        ),
        "llamacpp" => AiProviderConfig.new(
          "llamacpp",
          "openai-chat",
          "http://127.0.0.1:8080/v1",
          nil,
          false,
          {} of String => String,
          "local",
          {} of String => AiModelConfig
        ),
      }
    end

    def self.default_servers : Hash(String, ServerConfig)
      actors = [
        ActorConfig.new("code", "@code", "/inbox/code", "/outbox/code", "code"),
        ActorConfig.new("plan", "@plan", "/inbox/plan", "/outbox/plan", "plan"),
        ActorConfig.new("search", "@search", "/inbox/search", "/outbox/search", "search"),
      ]
      {
        "lefine.pro" => ServerConfig.new(
          "lefine.pro",
          "https://lefine.pro",
          "https://lefine.pro/actor/shell",
          "/inbox",
          "/outbox",
          nil,
          actors
        ),
      }
    end

    private def self.expand_home(s : String) : String
      if s.includes?("$HOME")
        s.gsub("$HOME", Xdg.home)
      else
        s
      end
    end

    private def self.parse_server(name : String, block : Rcl::Block) : ServerConfig
      base_url = required_string(block, "base_url")
      actor_id = string_property(block, "actor_id") || "#{base_url}/actor/shell"
      inbox = string_property(block, "inbox") || "/inbox"
      outbox = string_property(block, "outbox") || "/outbox"
      signature = nil.as(HttpSignatureConfig?)
      actors = [] of ActorConfig

      block.blocks.each do |child|
        case child.name
        when "http_signature"
          signature = HttpSignatureConfig.new(
            required_string(child, "key_id"),
            expand_home(required_string(child, "private_key_path")),
            string_property(child, "algorithm") || "rsa-sha256"
          )
        when "actor"
          actor_name = child.argument || raise Rcl::Error.new("actor block requires a name")
          command = string_property(child, "command") || "@#{actor_name}"
          actors << ActorConfig.new(
            actor_name,
            command,
            string_property(child, "inbox") || inbox,
            string_property(child, "outbox") || outbox,
            string_property(child, "work_type") || actor_name
          )
        end
      end

      ServerConfig.new(name, base_url.gsub(/\/+$/, ""), actor_id, inbox, outbox, signature, actors)
    end

    private def self.parse_provider(name : String, block : Rcl::Block) : AiProviderConfig
      api = string_property(block, "api") || "openai-responses"
      base_url = string_property(block, "base_url") || "https://api.openai.com/v1"
      api_key = string_property(block, "api_key") || "OPENAI_API_KEY"
      auth_header = bool_property(block, "auth_header", true)
      default_model = string_property(block, "default_model")
      headers = {} of String => String
      models = {} of String => AiModelConfig

      block.blocks.each do |child|
        case child.name
        when "header"
          key = child.argument || raise Rcl::Error.new("header block requires a name")
          headers[key] = required_string(child, "value")
        when "model"
          model_name = child.argument || raise Rcl::Error.new("model block requires a name")
          models[model_name] = AiModelConfig.new(model_name, string_property(child, "reasoning_effort"))
        end
      end

      AiProviderConfig.new(name, api, base_url.gsub(/\/+$/, ""), api_key, auth_header, headers, default_model, models, string_property(block, "server"), string_property(block, "actor"))
    end

    private def self.parse_extension(name : String, block : Rcl::Block) : ExtensionConfig
      command = required_string(block, "command")
      events = array_property(block, "events")
      ExtensionConfig.new(name, command, events)
    end

    private def self.parse_file_editor(block : Rcl::Block) : FileEditorConfig
      name = block.argument || "filetype"
      editor = string_property(block, "editor") || string_property(block, "command") || raise Rcl::Error.new("filetype #{name} requires editor")
      patterns = array_property(block, "patterns")
      extensions = array_property(block, "extensions")
      if patterns.empty? && extensions.empty?
        patterns = [name]
      end
      FileEditorConfig.new(name, patterns, extensions, editor)
    end

    private def self.parse_at(block : Rcl::Block?) : AtConfig
      defaults = default_at_config
      return defaults unless block

      actions = [] of AtMenuActionConfig
      block.blocks.each do |child|
        case child.name
        when "action"
          name = child.argument || raise Rcl::Error.new("at action block requires a name")
          kind = string_property(child, "kind") || "org_todo"
          label = string_property(child, "label") || name
          path = string_property(child, "org_todo_path").try { |p| expand_home(p) }
          category = string_property(child, "category")
          executor = string_property(child, "executor") || string_property(child, "assignee")
          actions << AtMenuActionConfig.new(name, label, kind, path, category, executor, string_property(child, "provider"), string_property(child, "model"), array_property(child, "prompt_modes"))
        end
      end

      AtConfig.new(actions.empty? ? defaults.menu_actions : actions)
    end

    private def self.parse_permissions(block : Rcl::Block?) : PermissionsConfig
      return PermissionsConfig.default unless block

      mode = PermissionMode.from(string_property(block, "mode") || string_property(block, "default_mode"))
      sandbox = bool_property(block, "sandbox", false)
      doom_loop_threshold = int_property(block, "doom_loop_threshold") || int_property(block, "doom-loop-threshold") || 8
      tools = [] of ToolPermissionConfig

      block.blocks.each do |child|
        case child.name
        when "tool"
          tool_name = child.argument || string_property(child, "name") || raise Rcl::Error.new("permissions tool block requires a name")
          tools << ToolPermissionConfig.new(tool_name, array_property(child, "allow"), array_property(child, "ask"), array_property(child, "deny"))
        end
      end

      PermissionsConfig.new(mode, sandbox, tools, doom_loop_threshold)
    end

    private def self.parse_permissions_json(any : JSON::Any?) : PermissionsConfig
      return PermissionsConfig.default unless any
      h = any.as_h?
      return PermissionsConfig.default unless h

      mode = PermissionMode.from(h["mode"]?.try(&.as_s?) || h["default_mode"]?.try(&.as_s?))
      sandbox = h["sandbox"]?.try(&.as_bool?) || false
      doom_loop_threshold = h["doom_loop_threshold"]?.try(&.as_i?) || h["doom-loop-threshold"]?.try(&.as_i?) || 8
      tools = [] of ToolPermissionConfig

      if list = h["tools"]?.try(&.as_a?)
        list.each do |item|
          next unless tool = item.as_h?
          tool_name = tool["name"]?.try(&.as_s?) || next
          allow = tool["allow"]?.try(&.as_a?).try { |a| a.compact_map(&.as_s?) } || [] of String
          ask = tool["ask"]?.try(&.as_a?).try { |a| a.compact_map(&.as_s?) } || [] of String
          deny = tool["deny"]?.try(&.as_a?).try { |a| a.compact_map(&.as_s?) } || [] of String
          tools << ToolPermissionConfig.new(tool_name, allow, ask, deny)
        end
      end

      PermissionsConfig.new(mode, sandbox, tools, doom_loop_threshold.to_i)
    rescue
      PermissionsConfig.default
    end

    private def self.required_string(block : Rcl::Block, key : String) : String
      string_property(block, key) || raise Rcl::Error.new("#{block.name} requires #{key}")
    end

    private def self.string_property(block : Rcl::Block?, key : String) : String?
      return nil unless block
      value = block.properties[key]?
      return nil unless value
      value.to_s
    end

    private def self.bool_property(block : Rcl::Block?, key : String, default : Bool) : Bool
      return default unless block
      value = block.properties[key]?
      return default unless value
      value.as(Bool)
    rescue
      default
    end

    private def self.int_property(block : Rcl::Block?, key : String) : Int32?
      return nil unless block
      value = block.properties[key]?
      return nil unless value
      case value
      when Float64
        value.to_i
      when String
        value.to_i?
      else
        value.to_s.to_i?
      end
    end

    private def self.array_property(block : Rcl::Block?, key : String) : Array(String)
      return [] of String unless block
      value = block.properties[key]?
      return [] of String unless value
      case value
      when Array(Rcl::Scalar)
        value.map(&.to_s)
      else
        [] of String
      end
    end

    private def self.parse_render(any : JSON::Any?) : Render::Config
      return Render::Config.default unless any
      h = any.as_h?
      return Render::Config.default unless h

      default_mode = Render::Mode.parse(h["default_mode"]?.try(&.as_s?)) || Render::Mode::Auto

      table = Render::TableConfig.default
      if th = h["table"]?.try(&.as_h?)
        max_rows = th["max_rows"]?.try(&.as_i?) || table.max_rows
        max_columns = th["max_columns"]?.try(&.as_i?) || table.max_columns
        max_cell_width = th["max_cell_width"]?.try(&.as_i?) || table.max_cell_width
        table = Render::TableConfig.new(max_rows.to_i, max_columns.to_i, max_cell_width.to_i)
      end

      pickers = Render::PickersConfig.default
      if ph = h["pickers"]?.try(&.as_h?)
        prefer_fzf = ph["prefer_fzf"]?.try(&.as_bool?)
        prefer_fzf = pickers.prefer_fzf if prefer_fzf.nil?
        pickers = Render::PickersConfig.new(prefer_fzf)
      end

      interactive = Render::InteractiveConfig.default
      if ih = h["interactive"]?.try(&.as_h?)
        enabled = ih["enabled"]?.try(&.as_bool?)
        enabled = interactive.enabled if enabled.nil?
        dt = Render::DateTimeConfig.default
        if dth = ih["datetime"]?.try(&.as_h?)
          days_ahead = dth["days_ahead"]?.try(&.as_i?) || dt.days_ahead
          tz = dth["default_timezone"]?.try(&.as_s?) || dt.default_timezone
          dt = Render::DateTimeConfig.new(days_ahead.to_i, tz)
        end
        interactive = Render::InteractiveConfig.new(enabled, dt)
      end

      ops = {} of String => Render::OperationRule
      if oh = h["operations"]?.try(&.as_h?)
        oh.each do |op_key, op_any|
          next unless oph = op_any.as_h?
          next unless bh = oph["body"]?.try(&.as_h?)
          body_type = bh["type"]?.try(&.as_s?) || "object"
          fields = [] of Render::FieldRule
          if fa = bh["fields"]?.try(&.as_a?)
            fa.each do |f_any|
              next unless fh = f_any.as_h?
              pointer = fh["pointer"]?.try(&.as_s?) || next
              kind_s = fh["kind"]?.try(&.as_s?) || "string"
              prompt = fh["prompt"]?.try(&.as_s?) || pointer
              required = fh["required"]?.try(&.as_bool?) || false

              kind =
                case kind_s.downcase
                when "string"   then Render::FieldKind::String
                when "boolean"  then Render::FieldKind::Boolean
                when "enum"     then Render::FieldKind::Enum
                when "datetime" then Render::FieldKind::DateTime
                when "file"     then Render::FieldKind::File
                when "json"     then Render::FieldKind::Json
                else                 Render::FieldKind::String
                end

              enum_values = [] of String
              if kind == Render::FieldKind::Enum
                if eva = fh["values"]?.try(&.as_a?)
                  enum_values = eva.compact_map(&.as_s?)
                end
              end

              default_bool = nil.as(Bool?)
              if kind == Render::FieldKind::Boolean
                default_bool = fh["default"]?.try(&.as_bool?)
              end

              fields << Render::FieldRule.new(pointer, kind, prompt, required, enum_values, default_bool)
            end
          end
          ops[op_key] = Render::OperationRule.new(body_type, fields)
        end
      end

      Render::Config.new(default_mode, table, pickers, interactive, ops)
    rescue
      Render::Config.default
    end
  end
end
