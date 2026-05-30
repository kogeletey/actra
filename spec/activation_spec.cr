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
    script.should contain("@stats|@statistics) command actra @ --action stats")
    script.should contain("function '?' { command actra query")
    script.should contain("function '@' {")
    script.should contain("local output exit_status")
    script.should_not contain("local output status")
    script.should_not contain("function '@?'")
    script.should_not contain("function '@file'")
    script.should_not contain("function '@assistant'")
    script.should_not contain("function '@agent'")
    script.should_not contain("function '@run'")
    script.should_not contain("function '@background'")
    script.should_not contain("function '@remote'")
    script.should_not contain("function '@container'")
    script.should_not contain("function '@stats'")
    script.should contain("_actra_complete_at")
    script.should contain("complete at")
    script.should contain("compdef _actra_complete_at actra '@'")
    script.should_not contain("compdef _actra_complete_at actra '@' '@?'")
    script.should_not contain("_actra_complete_file")
    script.should_not contain("compdef _actra_complete_file")
    script.should_not contain("function '@code'")
    script.should contain("_actra_at_root_mode()")
    script.should_not contain("function '@codex'")
    script.should contain("actra_auth_status")
    script.should contain("actra dispatch")
    script.should contain("ACTRA_AT_ACTIONS=()")
    script.should contain("if [[ -n \"$query\" ]]; then")
    script.should contain("candidates=(agent run background remote container)")
    script.should contain("agent) echo \"run agent\"")
    script.should contain("if (( count <= 0 )); then")
    script.should contain("ACTRA_AT_ACTION_INDEX=$(( (${ACTRA_AT_ACTION_INDEX:-0} % count) + 1 ))")
    script.should contain("ACTRA_AT_ACTION_INDEX=$count")
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
    script.should_not contain("agents) echo \"agents\"")
    script.should contain("agents\" \"*) query=\"${query#agents }\"")
    script.should contain("_actra_at_mode_mode")
    script.should contain("[[ \"${line:0:1}\" == \"@\" ]]")
    script.should contain("_actra_at_next_mode")
    script.should contain("_actra_at_next_mode \"$BUFFER\"")
    script.should contain("_actra_at_prev_mode")
    script.should contain("_actra_at_prev_mode \"$BUFFER\"")
    script.should contain("_actra_at_show_mode_preview")
    script.should contain("_actra_at_clear_preview")
    script.should contain("agent|run|background|remote|container|stats)")
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
    script.should contain("@stats|@statistics) command actra @ --action stats")
    script.should contain("?() { command actra query")
    script.should contain("function @ {")
    script.should contain("local output exit_status")
    script.should_not contain("local output status")
    script.should_not contain("function @?")
    script.should_not contain("@file()")
    script.should_not contain("alias @assistant=")
    script.should_not contain("alias @agent=")
    script.should_not contain("alias @run=")
    script.should_not contain("alias @background=")
    script.should_not contain("alias @remote=")
    script.should_not contain("alias @container=")
    script.should_not contain("alias @stats=")
    script.should contain("_actra_at_root_mode()")
    script.should contain("_actra_complete_at")
    script.should contain("complete at")
    script.should contain("complete -F _actra_complete_at actra @")
    script.should_not contain("complete -F _actra_complete_at actra @ @?")
    script.should_not contain("_actra_complete_file")
    script.should_not contain("complete -F _actra_complete_file")
    script.should_not contain("alias @code")
    script.should contain("_actra_at_root_mode()")
    script.should contain("if _actra_at_mode_mode \"$READLINE_LINE\"; then")
    script.should_not contain("alias @claude")
    script.should_not contain("alias @codex")
    script.should contain("actra_auth_status")
    script.should contain("actra dispatch")
    script.should contain("ACTRA_AT_ACTIONS=()")
    script.should contain("if [[ -n \"$query\" ]]; then")
    script.should contain("candidates=(agent run background remote container)")
    script.should contain("agent) printf '%s' \"run agent\"")
    script.should contain("if (( count <= 0 )); then")
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
    script.should_not contain("agents) printf '%s' \"agents\"")
    script.should contain("agents\" \"*) query=\"${query#agents }\"")
    script.should contain("[[ \"$1\" == \"@action\" || \"$1\" == \"@action \"* || \"$1\" == \"@actions\" || \"$1\" == \"@actions \"* ]]")
    script.should contain("[[ \"${1:0:1}\" == \"@\" ]]")
    script.should contain("_actra_at_next_mode \"$READLINE_LINE\"")
    script.should contain("_actra_at_prev_mode \"$READLINE_LINE\"")
    script.should contain("_actra_at_show_mode_preview")
    script.should contain("_actra_at_clear_preview")
    script.should contain("agent|run|background|remote|container|stats)")
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
        File.exists?(Actra::Xdg.config_path).should be_true
        File.read(Actra::Xdg.config_path).should contain("filetype \"code\"")
        File.read(Actra::Xdg.config_path).should contain("provider \"ollama\"")
        File.read(Actra::Xdg.config_path).should contain("provider \"llama.cpp\"")
        File.read(Actra::Xdg.config_path).should contain("permissions do")
        File.read(Actra::Xdg.config_path).should_not contain("org_todo")
        File.read(Actra::Xdg.config_path).should_not contain("default_server")
        File.read(Actra::Xdg.config_path).should_not contain("server \"")
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
        FileUtils.mkdir_p(Actra::Xdg.config_dir)
        File.write(Actra::Xdg.config_path, %(base do\n  default_server = "custom.example"\nend\n))

        stdout = IO::Memory.new
        stderr = IO::Memory.new

        code = Actra::CLI.run(["activate", "bash"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        File.read(Actra::Xdg.config_path).should contain("custom.example")
        File.read(Actra::Xdg.config_path).should_not contain("filetype \"code\"")
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
        File.exists?(Actra::Xdg.config_path).should be_true
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
