require "./xdg"

module Actra
  module Activation
    def self.script(shell : String, binary : String = "actra") : String
      case shell
      when "zsh"
        zsh(binary)
      when "bash"
        bash(binary)
      else
        raise "unsupported shell: #{shell} (expected bash or zsh)"
      end
    end

    def self.install(shell : String, binary : String = "actra") : String
      path =
        case shell
        when "zsh"
          File.join(Xdg.home, ".zshrc")
        when "bash"
          File.join(Xdg.home, ".bashrc")
        else
          raise "unsupported shell: #{shell} (expected bash or zsh)"
        end

      begin_marker = "# >>> actra activate >>>"
      end_marker = "# <<< actra activate <<<"
      block = "#{begin_marker}\n#{script(shell, binary)}\n#{end_marker}\n"
      existing = File.exists?(path) ? File.read(path) : ""

      if existing.includes?(begin_marker)
        updated = existing.gsub(/# >>> actra activate >>>.*?# <<< actra activate <<<\n?/m, block)
      else
        updated = existing
        updated += "\n" unless updated.empty? || updated.ends_with?("\n")
        updated += block
      end

      File.write(path, updated)
      path
    end

    def self.auth_script(shell : String) : String
      case shell
      when "zsh", "bash"
        <<-SH
        export LEFINE_TOKEN="${LEFINE_TOKEN:-}"
        export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
        export OPENAI_API_KEY="${OPENAI_API_KEY:-}"
        export ACTRA_LAUNCH_REMOTE="${ACTRA_LAUNCH_REMOTE:-@code}"
        export ACTRA_DEFAULT_SERVER="${ACTRA_DEFAULT_SERVER:-lefine.pro}"
        SH
      else
        raise "unsupported shell: #{shell} (expected bash or zsh)"
      end
    end

    private def self.auth_helpers : String
      <<-SH
      actra_auth_status() {
        [ -n "$LEFINE_TOKEN" ] && printf 'LEFINE_TOKEN=set\\n' || printf 'LEFINE_TOKEN=missing\\n'
        [ -n "$ANTHROPIC_API_KEY" ] && printf 'ANTHROPIC_API_KEY=set\\n' || printf 'ANTHROPIC_API_KEY=missing\\n'
        [ -n "$OPENAI_API_KEY" ] && printf 'OPENAI_API_KEY=set\\n' || printf 'OPENAI_API_KEY=missing\\n'
      }
      SH
    end

    private def self.zsh(binary : String) : String
      <<-ZSH
      #{auth_helpers}

      _actra_dispatch() {
        local cmd="$1"
        shift
        command #{binary} dispatch --command "$cmd" -- "$@"
      }

      _actra_query() {
        local cmd="${1#?}"
        shift
        if [ -n "$cmd" ]; then
          command #{binary} query "$cmd" -- "$@"
        else
          command #{binary} query "$@"
        fi
      }

      function '?' { command #{binary} query "$@"; }
      function '@' { command #{binary} @ "$@"; }
      function '@?' { command #{binary} @? "$@"; }
      function '@file' { command #{binary} @file "$@"; }
      function '@code' { _actra_dispatch "@code" "$@"; }
      function '@plan' { _actra_dispatch "@plan" "$@"; }
      function '@claude' { _actra_dispatch "@claude" "$@"; }
      function '@codex' { _actra_dispatch "@codex" "$@"; }

      _actra_complete_at() {
        local -a matches
        matches=("${(@f)$(command #{binary} complete at "$PREFIX" 2>/dev/null)}")
        compadd -Q -- "${matches[@]}"
      }

      _actra_register_completions() {
        local -a commands
        commands=("${(@f)$(command #{binary} complete actors 2>/dev/null)}")
        compdef _actra_complete_at #{binary} '@' '@file' '@?'
        local cmd
        for cmd in "$commands[@]"; do
          compdef _actra_complete_at "$cmd"
        done
      }
      _actra_register_completions

      command_not_found_handler() {
        case "$1" in
          @) command #{binary} @ "${@:2}" ;;
          @\\?) command #{binary} @? "${@:2}" ;;
          \\?*) _actra_query "$@" ;;
          @*) _actra_dispatch "$@" ;;
          *) return 127 ;;
        esac
      }
      ZSH
    end

    private def self.bash(binary : String) : String
      <<-BASH
      #{auth_helpers}

      _actra_dispatch() {
        local cmd="$1"
        shift
        command #{binary} dispatch --command "$cmd" -- "$@"
      }

      _actra_query() {
        local cmd="${1#?}"
        shift
        if [ -n "$cmd" ]; then
          command #{binary} query "$cmd" -- "$@"
        else
          command #{binary} query "$@"
        fi
      }

      ?() { command #{binary} query "$@"; }
      function @ { command #{binary} @ "$@"; }
      function @? { command #{binary} @? "$@"; }
      @file() { command #{binary} @file "$@"; }
      alias @code='_actra_dispatch @code'
      alias @plan='_actra_dispatch @plan'
      alias @claude='_actra_dispatch @claude'
      alias @codex='_actra_dispatch @codex'

      _actra_complete_at() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        mapfile -t COMPREPLY < <(command #{binary} complete at "$cur" 2>/dev/null)
      }

      _actra_register_completions() {
        complete -F _actra_complete_at #{binary} @ @file @?
        local cmd
        while IFS= read -r cmd; do
          [ -n "$cmd" ] && complete -F _actra_complete_at "$cmd"
        done < <(command #{binary} complete actors 2>/dev/null)
      }
      _actra_register_completions

      command_not_found_handle() {
        case "$1" in
          @) command #{binary} @ "${@:2}" ;;
          @\\?) command #{binary} @? "${@:2}" ;;
          \\?*) _actra_query "$@" ;;
          @*) _actra_dispatch "$@" ;;
          *) return 127 ;;
        esac
      }
      BASH
    end
  end
end
