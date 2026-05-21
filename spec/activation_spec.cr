require "spec"
require "file_utils"

require "../src/actra/activation"
require "../src/actra/cli"
require "./support/tmpdir"

describe Actra::Activation do
  it "prints zsh dispatch hooks for @ commands" do
    script = Actra::Activation.script("zsh")
    script.should contain("_actra_dispatch")
    script.should contain("_actra_query")
    script.should contain("command_not_found_handler")
    script.should contain("\\?*) _actra_query")
    script.should contain("function '?' { command actra query")
    script.should contain("function '@' {")
    script.should contain("local output exit_status")
    script.should_not contain("local output status")
    script.should_not contain("function '@?'")
    script.should_not contain("function '@file'")
      script.should contain("function '@assistant'")
      script.should contain("function '@agent'")
      script.should contain("function '@run'")
      script.should contain("function '@background'")
      script.should contain("function '@remote'")
      script.should contain("function '@container'")
      script.should contain("function '@stats'")
    script.should contain("_actra_complete_at")
    script.should contain("complete at")
    script.should contain("compdef _actra_complete_at actra '@'")
    script.should_not contain("compdef _actra_complete_at actra '@' '@?'")
    script.should_not contain("_actra_complete_file")
    script.should_not contain("compdef _actra_complete_file")
    script.should contain("function '@code'")
      script.should contain("_actra_at_root_mode()")
      script.should contain("@claude")
      script.should contain("@codex")
      script.should contain("actra_auth_status")
      script.should contain("actra dispatch")
      script.should contain("ACTRA_AT_ACTIONS=(code assistant agent run background remote container)")
      script.should contain("if _actra_at_mode_mode \"$BUFFER\"; then")
      script.should contain("_actra_at_tab_action")
      script.should contain("_actra_at_shift_tab_action")
      script.should contain("_actra_at_show_action_preview")
      script.should contain("ACTRA_AT_ACTION_QUERY_CACHE")
      script.should contain("ACTRA_AT_ACTION_PREVIEW_CACHE_KEY")
      script.should contain("ACTRA_AT_FILE_PREVIEW_CACHE_KEY")
      script.should contain("_actra_at_action_preview_cached")
      script.should contain("_actra_at_file_preview_cached")
      script.should_not contain("zle -M")
      script.should_not contain("zle -I")
      script.should contain("|         @ mode picker         |")
      script.should contain("_actra_at_action_preview_cached \"$ACTRA_AT_ACTION\" \"$query\"")
    script.should contain("bindkey '^I' _actra_at_tab_action")
    script.should contain("bindkey 'j' _actra_at_j_action")
    script.should contain("bindkey 'k' _actra_at_k_action")
    script.should contain("bindkey '^[[Z' _actra_at_shift_tab_action")
    script.should contain("bindkey -M emacs '^I' _actra_at_tab_action")
    script.should contain("bindkey -M emacs 'j' _actra_at_j_action")
    script.should contain("bindkey -M emacs 'k' _actra_at_k_action")
    script.should contain("bindkey -M emacs '^[[Z' _actra_at_shift_tab_action")
    script.should contain("bindkey -M viins '^I' _actra_at_tab_action")
    script.should contain("bindkey -M viins 'j' _actra_at_j_action")
    script.should contain("bindkey -M viins 'k' _actra_at_k_action")
    script.should contain("bindkey -M viins '^[[Z' _actra_at_shift_tab_action")
    script.should contain("[[ \"$line\" == \"@action\" || \"$line\" == \"@action \"* || \"$line\" == \"@actions\" || \"$line\" == \"@actions \"* ]]")
      script.should contain("@ --action \"$action\"")
      script.should contain("ACTRA_AT_MODES=(actions files stats)")
      script.should contain("_actra_at_mode_mode")
      script.should contain("[[ \"${line:0:1}\" == \"@\" ]]")
      script.should contain("_actra_at_next_mode")
      script.should contain("_actra_at_prev_mode")
      script.should contain("bindkey '^[[B' _actra_at_down_action")
      script.should contain("bindkey '^[[A' _actra_at_up_action")
      script.should contain("bindkey -M emacs '^[[B' _actra_at_down_action")
      script.should contain("bindkey -M emacs '^[[A' _actra_at_up_action")
      script.should contain("bindkey -M viins '^[[B' _actra_at_down_action")
      script.should contain("bindkey -M viins '^[[A' _actra_at_up_action")
      script.should_not contain("@ --mode \"$mode\"")
    script.should_not contain("_actra_ctrl_at_menu")
    script.should_not contain("bindkey '^O'")
    script.should_not contain("bindkey $'\\e[13;5u'")
    script.should_not contain("bindkey $'\\e[1;5F'")
    script.should_not contain("actra @ --ctrl-enter")
  end

  it "prints bash dispatch hooks for @ commands" do
    script = Actra::Activation.script("bash")
    script.should contain("_actra_query")
    script.should contain("command_not_found_handle")
    script.should contain("\\?*) _actra_query")
    script.should contain("?() { command actra query")
    script.should contain("function @ {")
    script.should contain("local output exit_status")
    script.should_not contain("local output status")
    script.should_not contain("function @?")
    script.should_not contain("@file()")
      script.should contain("alias @assistant='actra @ --action assistant'")
      script.should contain("alias @agent='actra @ --action agent'")
      script.should contain("alias @run='actra @ --action run'")
      script.should contain("alias @background='actra @ --action background'")
      script.should contain("alias @remote='actra @ --action remote'")
      script.should contain("alias @container='actra @ --action container'")
      script.should contain("alias @stats='actra @ --action stats'")
      script.should contain("_actra_at_root_mode()")
      script.should contain("_actra_complete_at")
    script.should contain("complete at")
    script.should contain("complete -F _actra_complete_at actra @")
    script.should_not contain("complete -F _actra_complete_at actra @ @?")
    script.should_not contain("_actra_complete_file")
    script.should_not contain("complete -F _actra_complete_file")
      script.should contain("alias @code")
      script.should contain("_actra_at_root_mode()")
      script.should contain("if _actra_at_mode_mode \"$READLINE_LINE\"; then")
      script.should contain("alias @claude")
      script.should contain("alias @codex")
      script.should contain("actra_auth_status")
      script.should contain("actra dispatch")
      script.should contain("ACTRA_AT_ACTIONS=(code assistant agent run background remote container)")
      script.should contain("_actra_at_tab_action")
      script.should contain("_actra_at_shift_tab_action")
      script.should contain("_actra_at_show_action_preview")
      script.should contain("ACTRA_AT_ACTION_QUERY_CACHE")
      script.should contain("ACTRA_AT_ACTION_PREVIEW_CACHE_KEY")
      script.should contain("ACTRA_AT_FILE_PREVIEW_CACHE_KEY")
      script.should contain("_actra_at_action_preview_cached")
      script.should contain("_actra_at_file_preview_cached")
      script.should contain("|         @ mode picker         |")
      script.should contain("printf '\\n+------------------------------+\\\\n'")
      script.should contain("printf '\e7'")
      script.should contain("printf '\e8'")
      script.should contain("_actra_at_action_preview_cached \"$ACTRA_AT_ACTION\" \"$query\"")
    script.should contain("bind -x")
    script.should contain("bind -x '\"\\C-i\": _actra_at_tab_action'")
    script.should contain("bind -x '\"\\e[Z\": _actra_at_shift_tab_action'")
    script.should contain("bind -x '\"\\e[A\": _actra_at_up_action'")
    script.should contain("bind -x '\"\\e[B\": _actra_at_down_action'")
      script.should contain("ACTRA_AT_MODES=(actions files stats)")
      script.should contain("[[ \"$1\" == \"@action\" || \"$1\" == \"@action \"* || \"$1\" == \"@actions\" || \"$1\" == \"@actions \"* ]]")
      script.should contain("[[ \"${1:0:1}\" == \"@\" ]]")
      script.should contain("@ --action \"$action\"")
    script.should_not contain("@ --mode \"$mode\"")
    script.should_not contain("_actra_ctrl_at_menu")
    script.should_not contain("\\e[13;5u")
    script.should_not contain("\\e[1;5F")
    script.should_not contain("actra @ --ctrl-enter")
  end

  it "creates the default config when activate runs without an existing config" do
    SpecTmpdir.with do |root|
      old_root = ENV["ACTRA_TEST_ROOT"]?
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        stdout = IO::Memory.new
        stderr = IO::Memory.new

        code = Actra::CLI.run(["activate", "bash"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        File.exists?(Actra::Xdg.astra_config_path).should be_true
        File.read(Actra::Xdg.astra_config_path).should contain("filetype \"code\"")
        File.read(Actra::Xdg.astra_config_path).should contain("provider \"ollama\"")
        File.read(Actra::Xdg.astra_config_path).should contain("provider \"llama.cpp\"")
        File.read(Actra::Xdg.astra_config_path).should contain("permissions do")
        File.read(Actra::Xdg.astra_config_path).should_not contain("org_todo")
        stdout.to_s.should contain("function @")
        stdout.to_s.should_not contain("created:")
      ensure
        if old_root
          ENV["ACTRA_TEST_ROOT"] = old_root
        else
          ENV.delete("ACTRA_TEST_ROOT")
        end
      end
    end
  end

  it "does not overwrite an existing config when activate runs" do
    SpecTmpdir.with do |root|
      old_root = ENV["ACTRA_TEST_ROOT"]?
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
        File.write(Actra::Xdg.astra_config_path, %(base do\n  default_server = "custom.example"\nend\n))

        stdout = IO::Memory.new
        stderr = IO::Memory.new

        code = Actra::CLI.run(["activate", "bash"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        File.read(Actra::Xdg.astra_config_path).should contain("custom.example")
        File.read(Actra::Xdg.astra_config_path).should_not contain("filetype \"code\"")
      ensure
        if old_root
          ENV["ACTRA_TEST_ROOT"] = old_root
        else
          ENV.delete("ACTRA_TEST_ROOT")
        end
      end
    end
  end

  it "creates the default config when shell alias generation runs" do
    SpecTmpdir.with do |root|
      old_root = ENV["ACTRA_TEST_ROOT"]?
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        stdout = IO::Memory.new
        stderr = IO::Memory.new

        code = Actra::CLI.run(["shell", "bash", "@example.org"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        File.exists?(Actra::Xdg.astra_config_path).should be_true
        stdout.to_s.should contain("alias example")
      ensure
        if old_root
          ENV["ACTRA_TEST_ROOT"] = old_root
        else
          ENV.delete("ACTRA_TEST_ROOT")
        end
      end
    end
  end
end
