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
      typeset -ga ACTRA_AT_ACTIONS=(code assistant agent run background remote container)
      typeset -g ACTRA_AT_ACTION_INDEX=-1
      typeset -g ACTRA_AT_ACTION=""
      typeset -ga ACTRA_AT_MODES=(actions files stats)
      typeset -g ACTRA_AT_MODE_INDEX=-1
      typeset -g ACTRA_AT_MODE=""
      typeset -g ACTRA_AT_ACTION_QUERY_CACHE=""
      typeset -g ACTRA_AT_ACTION_CANDIDATES_LOADED=0
      typeset -g ACTRA_AT_ACTION_PREVIEW_CACHE_KEY=""
      typeset -g ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE=""
      typeset -g ACTRA_AT_FILE_PREVIEW_CACHE_KEY=""
      typeset -g ACTRA_AT_FILE_PREVIEW_CACHE_VALUE=""

      _actra_at_action_label() {
        case "$1" in
          code) echo "code" ;;
          assistant) echo "assistant (AI)" ;;
          agent) echo "agent (AI)" ;;
          run) echo "run local" ;;
          background) echo "background" ;;
          remote) echo "remote" ;;
          container) echo "container" ;;
          *) echo "$1" ;;
        esac
      }

      _actra_at_next_action() {
        local count="${#ACTRA_AT_ACTIONS[@]}"
        ACTRA_AT_ACTION_INDEX=$(( (${ACTRA_AT_ACTION_INDEX:--1} + 1) % count ))
        ACTRA_AT_ACTION="${ACTRA_AT_ACTIONS[$ACTRA_AT_ACTION_INDEX]}"
      }

      _actra_at_prev_action() {
        local count="${#ACTRA_AT_ACTIONS[@]}"
        if (( ${ACTRA_AT_ACTION_INDEX:--1} < 0 )); then
          ACTRA_AT_ACTION_INDEX=$(( count - 1 ))
        else
          ACTRA_AT_ACTION_INDEX=$(( (ACTRA_AT_ACTION_INDEX + count - 1) % count ))
        fi
        ACTRA_AT_ACTION="${ACTRA_AT_ACTIONS[$ACTRA_AT_ACTION_INDEX]}"
      }

      _actra_at_load_action_candidates() {
        local line="${1-}"
        local query output candidate
        local -a candidates=(code assistant agent run background remote container)
        query="$(_actra_at_action_query "$line")"
        if [[ "${ACTRA_AT_ACTION_CANDIDATES_LOADED:-0}" == "1" && "$ACTRA_AT_ACTION_QUERY_CACHE" == "$query" ]]; then
          return
        fi
        output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --mode-preview "actions" "$query" 2>/dev/null)"
        while IFS= read -r candidate; do
          case "$candidate" in
            action" "*)
              candidate="${candidate#action }"
              [[ "$candidate" == "stats" || "$candidate" == "statistics" ]] && continue
              ;;
            *)
              continue
          esac
          [[ -n "$candidate" ]] || continue
          candidates+=("$candidate")
        done <<< "$output"
        ACTRA_AT_ACTIONS=("${candidates[@]}")
        ACTRA_AT_ACTION_QUERY_CACHE="$query"
        ACTRA_AT_ACTION_CANDIDATES_LOADED=1
      }

      _actra_at_action_preview_cached() {
        local action="$1"
        local query="${2:-}"
        local key="${action}"$'\t'"${query}"

        if [[ "$ACTRA_AT_ACTION_PREVIEW_CACHE_KEY" == "$key" ]]; then
          printf '%s\n' "$ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE"
          return
        fi

        ACTRA_AT_ACTION_PREVIEW_CACHE_KEY="$key"
        ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --action-preview "$action" "$query" 2>&1)"
        printf '%s\n' "$ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE"
      }

      _actra_at_file_preview_cached() {
        local query="${1:-}"

        if [[ "$ACTRA_AT_FILE_PREVIEW_CACHE_KEY" == "$query" ]]; then
          printf '%s\n' "$ACTRA_AT_FILE_PREVIEW_CACHE_VALUE"
          return
        fi

        ACTRA_AT_FILE_PREVIEW_CACHE_KEY="$query"
        ACTRA_AT_FILE_PREVIEW_CACHE_VALUE="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --mode-preview "files" "$query" 2>&1)"
        printf '%s\n' "$ACTRA_AT_FILE_PREVIEW_CACHE_VALUE"
      }

      _actra_at_action_mode() {
        local line="${1-}"
        [[ "$line" == "@action" || "$line" == "@action "* || "$line" == "@actions" || "$line" == "@actions "* ]]
      }

      _actra_at_root_mode() {
        local line="${1-}"
        [[ "$line" == "@" || "$line" == "@ "* ]]
      }

      _actra_at_mode_mode() {
        local line="${1-}"
        [[ "${line:0:1}" == "@" ]]
      }

      _actra_at_mode_label() {
        case "$1" in
          actions) echo "actions" ;;
          files) echo "files" ;;
          stats) echo "statistics" ;;
          *) echo "$1" ;;
        esac
      }

      _actra_at_next_mode() {
        local line="${1-}"
        local count="${#ACTRA_AT_MODES[@]}"
        ACTRA_AT_MODE_INDEX=$(( (${ACTRA_AT_MODE_INDEX:--1} + 1) % count ))
        ACTRA_AT_MODE="${ACTRA_AT_MODES[$ACTRA_AT_MODE_INDEX]}"
        if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
          ACTRA_AT_ACTION_INDEX=-1
          _actra_at_load_action_candidates "$line"
          _actra_at_next_action
        else
          if [[ "$ACTRA_AT_MODE" == "stats" ]]; then
            ACTRA_AT_ACTION="stats"
            ACTRA_AT_ACTION_INDEX=-1
          else
            ACTRA_AT_ACTION=""
            ACTRA_AT_ACTION_INDEX=-1
          fi
        fi
      }

      _actra_at_prev_mode() {
        local line="${1-}"
        local count="${#ACTRA_AT_MODES[@]}"
        if (( ${ACTRA_AT_MODE_INDEX:--1} < 0 )); then
          ACTRA_AT_MODE_INDEX=$(( count - 1 ))
        else
          ACTRA_AT_MODE_INDEX=$(( (ACTRA_AT_MODE_INDEX + count - 1) % count ))
        fi
        ACTRA_AT_MODE="${ACTRA_AT_MODES[$ACTRA_AT_MODE_INDEX]}"
        if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
          ACTRA_AT_ACTION_INDEX=-1
          _actra_at_load_action_candidates "$line"
          _actra_at_prev_action
        else
          if [[ "$ACTRA_AT_MODE" == "stats" ]]; then
            ACTRA_AT_ACTION="stats"
            ACTRA_AT_ACTION_INDEX=-1
          else
            ACTRA_AT_ACTION=""
            ACTRA_AT_ACTION_INDEX=-1
          fi
        fi
      }

      _actra_at_mode_query() {
        local line="${1-}"
        local query="${line#@}"
        case "$query" in
          action) query="";;
          action" "*) query="${query#action }";;
          actions) query="";;
          actions" "*) query="${query#actions }";;
          *) query="$query";;
        esac
        query="${query# }"
        printf '%s' "$query"
      }

      _actra_at_action_query() {
        local line="${1-}"
        local query="${line#@}"
        case "$query" in
          action) query="";;
          action" "*) query="${query#action }";;
          actions) query="";;
          actions" "*) query="${query#actions }";;
          *) query="$query";;
        esac
        query="${query# }"
        printf '%s' "$query"
      }

      _actra_at_print_mode_picker() {
        local candidate label
        printf '%s\n' "+------------------------------+"
        printf '%s\n' "|         @ mode picker         |"
        printf '%s\n' "+------------------------------+"
        for candidate in "${ACTRA_AT_MODES[@]}"; do
          label="$(_actra_at_mode_label "$candidate")"
          if [[ "$candidate" == "$ACTRA_AT_MODE" ]]; then
            printf '| > %-27s |\n' "$label"
          else
            printf '|   %-26s |\n' "$label"
          fi
        done
        printf '%s\n' "+------------------------------+"
      }

      _actra_at_render_preview() {
        printf '\e7'
        printf '\r'
        printf '\e[1E'
        printf '\r'
        printf '\e[0J'
      }

      _actra_at_show_mode_preview() {
        local query="$(_actra_at_mode_query "$BUFFER")"
        local output menu
        if [[ "$ACTRA_AT_MODE" == "stats" ]]; then
          output="$(_actra_at_action_preview_cached "stats" "$query")"
        elif [[ "$ACTRA_AT_MODE" == "files" ]]; then
          output="$(_actra_at_file_preview_cached "$query")"
        else
          output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --mode-preview "$ACTRA_AT_MODE" "$query" 2>&1)"
        fi
        menu="$(_actra_at_print_mode_picker)"
        [ -n "$output" ] && menu+=$'\n'"$output"
        _actra_at_render_preview
        print -r -- "$menu"
        printf '\e8'
      }

      _actra_at_show_action_preview() {
        local query="$(_actra_at_action_query "$BUFFER")"
        _actra_at_load_action_candidates "$BUFFER"
        local label
        local output menu
        output="$(_actra_at_action_preview_cached "$ACTRA_AT_ACTION" "$query")"
        menu="$(_actra_at_print_mode_picker)"
        for candidate in "${ACTRA_AT_ACTIONS[@]}"; do
          label="$(_actra_at_action_label "$candidate")"
          if [[ "$candidate" == "$ACTRA_AT_ACTION" ]]; then
            menu+=$'\n'"$(printf '| > %-27s |' "$label")"
          else
            menu+=$'\n'"$(printf '|   %-26s |' "$label")"
          fi
        done
        menu+=$'\n+------------------------------+'
        [[ -n "$output" ]] && menu+=$'\n'"$output"
        _actra_at_render_preview
        print -r -- "$menu"
        printf '\e8'
      }

      _actra_at_tab_action() {
        if _actra_at_action_mode "$BUFFER"; then
          _actra_at_load_action_candidates "$BUFFER"
          _actra_at_next_action
          _actra_at_show_action_preview
        elif _actra_at_mode_mode "$BUFFER"; then
          _actra_at_next_mode "$BUFFER"
          if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
            _actra_at_show_action_preview
          else
            _actra_at_show_mode_preview
          fi
        else
          zle expand-or-complete
        fi
      }

      _actra_at_down_action() {
        if _actra_at_mode_mode "$BUFFER" && [[ "$ACTRA_AT_MODE" == "actions" ]] || _actra_at_action_mode "$BUFFER"; then
          _actra_at_load_action_candidates "$BUFFER"
          _actra_at_next_action
          _actra_at_show_action_preview
        else
          zle down-line-or-beginning-search
        fi
      }

      _actra_at_up_action() {
        if _actra_at_mode_mode "$BUFFER" && [[ "$ACTRA_AT_MODE" == "actions" ]] || _actra_at_action_mode "$BUFFER"; then
          _actra_at_load_action_candidates "$BUFFER"
          _actra_at_prev_action
          _actra_at_show_action_preview
        else
          zle up-line-or-beginning-search
        fi
      }

      _actra_at_j_action() {
        if _actra_at_action_mode "$BUFFER" || (_actra_at_mode_mode "$BUFFER" && [[ "$ACTRA_AT_MODE" == "actions" ]]); then
          _actra_at_load_action_candidates "$BUFFER"
          _actra_at_next_action
          _actra_at_show_action_preview
        else
          zle self-insert
        fi
      }

      _actra_at_k_action() {
        if _actra_at_action_mode "$BUFFER" || (_actra_at_mode_mode "$BUFFER" && [[ "$ACTRA_AT_MODE" == "actions" ]]); then
          _actra_at_load_action_candidates "$BUFFER"
          _actra_at_prev_action
          _actra_at_show_action_preview
        else
          zle self-insert
        fi
      }

      _actra_at_shift_tab_action() {
        if _actra_at_action_mode "$BUFFER"; then
          _actra_at_load_action_candidates "$BUFFER"
          _actra_at_prev_action
          _actra_at_show_action_preview
        elif _actra_at_mode_mode "$BUFFER"; then
          _actra_at_prev_mode "$BUFFER"
          if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
            _actra_at_show_action_preview
          else
            _actra_at_show_mode_preview
          fi
        else
          zle reverse-menu-complete
        fi
      }
      zle -N _actra_at_tab_action
      zle -N _actra_at_down_action
      zle -N _actra_at_up_action
      zle -N _actra_at_j_action
      zle -N _actra_at_k_action
      zle -N _actra_at_shift_tab_action
      bindkey '^I' _actra_at_tab_action
      bindkey '^[[B' _actra_at_down_action
      bindkey '^[[A' _actra_at_up_action
      bindkey 'j' _actra_at_j_action
      bindkey 'k' _actra_at_k_action
      bindkey '^[[Z' _actra_at_shift_tab_action
      bindkey -M emacs '^I' _actra_at_tab_action 2>/dev/null
      bindkey -M emacs '^[[B' _actra_at_down_action 2>/dev/null
      bindkey -M emacs '^[[A' _actra_at_up_action 2>/dev/null
      bindkey -M emacs 'j' _actra_at_j_action 2>/dev/null
      bindkey -M emacs 'k' _actra_at_k_action 2>/dev/null
      bindkey -M emacs '^[[Z' _actra_at_shift_tab_action 2>/dev/null
      bindkey -M viins '^I' _actra_at_tab_action 2>/dev/null
      bindkey -M viins '^[[B' _actra_at_down_action 2>/dev/null
      bindkey -M viins '^[[A' _actra_at_up_action 2>/dev/null
      bindkey -M viins 'j' _actra_at_j_action 2>/dev/null
      bindkey -M viins 'k' _actra_at_k_action 2>/dev/null
      bindkey -M viins '^[[Z' _actra_at_shift_tab_action 2>/dev/null

      function '@' {
        local action="${ACTRA_AT_ACTION:-}"
        local output exit_status
        ACTRA_AT_ACTION=""
        ACTRA_AT_ACTION_INDEX=-1
        ACTRA_AT_MODE=""
        ACTRA_AT_MODE_INDEX=-1
        ACTRA_AT_ACTION_QUERY_CACHE=""
        ACTRA_AT_ACTION_CANDIDATES_LOADED=0
        ACTRA_AT_ACTION_PREVIEW_CACHE_KEY=""
        ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE=""
        ACTRA_AT_FILE_PREVIEW_CACHE_KEY=""
        ACTRA_AT_FILE_PREVIEW_CACHE_VALUE=""
        case "$action" in
          code|assistant|agent|run|background|remote|container|stats) output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --action "$action" "$@")"; exit_status=$? ;;
          *)
            if [[ -n "$action" ]]; then
              output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ "$action" "$@")"; exit_status=$?
            else
              output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ "$@")"; exit_status=$?
            fi
            ;;
        esac
        case "$output" in
          __ACTRA_INSERT__*)
            print -z -- "${output#__ACTRA_INSERT__}"
            ;;
          __ACTRA_CD__*)
            cd -- "${output#__ACTRA_CD__}"
            ;;
          *)
            [[ -n "$output" ]] && print -r -- "$output"
            ;;
        esac
        return "$exit_status"
      }
      function '@code' { _actra_dispatch "@code" "$@"; }
      function '@assistant' { command #{binary} @ --action assistant "$@"; }
      function '@agent' { command #{binary} @ --action agent "$@"; }
      function '@run' { command #{binary} @ --action run "$@"; }
      function '@background' { command #{binary} @ --action background "$@"; }
      function '@remote' { command #{binary} @ --action remote "$@"; }
      function '@container' { command #{binary} @ --action container "$@"; }
      function '@stats' { command #{binary} @ --action stats "$@"; }
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
        compdef _actra_complete_at #{binary} '@'
        local cmd
        for cmd in "$commands[@]"; do
          compdef _actra_complete_at "$cmd"
        done
      }
      _actra_register_completions

      command_not_found_handler() {
        case "$1" in
          @) command #{binary} @ "${@:2}" ;;
          @\\?) return 127 ;;
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
      ACTRA_AT_ACTIONS=(code assistant agent run background remote container)
      ACTRA_AT_ACTION_INDEX=-1
      ACTRA_AT_ACTION=""
      ACTRA_AT_MODES=(actions files stats)
      ACTRA_AT_MODE_INDEX=-1
      ACTRA_AT_MODE=""
      ACTRA_AT_ACTION_QUERY_CACHE=""
      ACTRA_AT_ACTION_CANDIDATES_LOADED=0
      ACTRA_AT_ACTION_PREVIEW_CACHE_KEY=""
      ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE=""
      ACTRA_AT_FILE_PREVIEW_CACHE_KEY=""
      ACTRA_AT_FILE_PREVIEW_CACHE_VALUE=""

      _actra_at_action_label() {
        case "$1" in
          code) printf '%s' "code" ;;
          assistant) printf '%s' "assistant (AI)" ;;
          agent) printf '%s' "agent (AI)" ;;
          run) printf '%s' "run local" ;;
          background) printf '%s' "background" ;;
          remote) printf '%s' "remote" ;;
          container) printf '%s' "container" ;;
          *) printf '%s' "$1" ;;
        esac
      }

      _actra_at_next_action() {
        local count="${#ACTRA_AT_ACTIONS[@]}"
        ACTRA_AT_ACTION_INDEX=$(( (${ACTRA_AT_ACTION_INDEX:--1} + 1) % count ))
        ACTRA_AT_ACTION="${ACTRA_AT_ACTIONS[$ACTRA_AT_ACTION_INDEX]}"
      }

      _actra_at_prev_action() {
        local count="${#ACTRA_AT_ACTIONS[@]}"
        if (( ${ACTRA_AT_ACTION_INDEX:--1} < 0 )); then
          ACTRA_AT_ACTION_INDEX=$(( count - 1 ))
        else
          ACTRA_AT_ACTION_INDEX=$(( (ACTRA_AT_ACTION_INDEX + count - 1) % count ))
        fi
        ACTRA_AT_ACTION="${ACTRA_AT_ACTIONS[$ACTRA_AT_ACTION_INDEX]}"
      }

      _actra_at_load_action_candidates() {
        local line="${1-}"
        local query output candidate
        local -a candidates=(code assistant agent run background remote container)
        query="$(_actra_at_action_query "$line")"
        if [[ "${ACTRA_AT_ACTION_CANDIDATES_LOADED:-0}" == "1" && "$ACTRA_AT_ACTION_QUERY_CACHE" == "$query" ]]; then
          return
        fi
        output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --mode-preview "actions" "$query" 2>/dev/null)"
        while IFS= read -r candidate; do
          case "$candidate" in
            action" "*)
              candidate="${candidate#action }"
              [[ "$candidate" == "stats" || "$candidate" == "statistics" ]] && continue
              ;;
            *)
              continue
          esac
          [[ -n "$candidate" ]] || continue
          candidates+=("$candidate")
        done <<< "$output"
        ACTRA_AT_ACTIONS=("${candidates[@]}")
        ACTRA_AT_ACTION_QUERY_CACHE="$query"
        ACTRA_AT_ACTION_CANDIDATES_LOADED=1
      }

      _actra_at_action_preview_cached() {
        local action="$1"
        local query="${2:-}"
        local key="${action}"$'\t'"${query}"

        if [[ "$ACTRA_AT_ACTION_PREVIEW_CACHE_KEY" == "$key" ]]; then
          printf '%s\n' "$ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE"
          return
        fi

        ACTRA_AT_ACTION_PREVIEW_CACHE_KEY="$key"
        ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --action-preview "$action" "$query" 2>&1)"
        printf '%s\n' "$ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE"
      }

      _actra_at_file_preview_cached() {
        local query="${1:-}"

        if [[ "$ACTRA_AT_FILE_PREVIEW_CACHE_KEY" == "$query" ]]; then
          printf '%s\n' "$ACTRA_AT_FILE_PREVIEW_CACHE_VALUE"
          return
        fi

        ACTRA_AT_FILE_PREVIEW_CACHE_KEY="$query"
        ACTRA_AT_FILE_PREVIEW_CACHE_VALUE="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --mode-preview "files" "$query" 2>&1)"
        printf '%s\n' "$ACTRA_AT_FILE_PREVIEW_CACHE_VALUE"
      }

      _actra_at_action_mode() {
        [[ "$1" == "@action" || "$1" == "@action "* || "$1" == "@actions" || "$1" == "@actions "* ]]
      }

      _actra_at_root_mode() {
        [[ "$1" == "@" || "$1" == "@ "* ]]
      }

      _actra_at_mode_mode() {
        [[ "${1:0:1}" == "@" ]]
      }

      _actra_at_mode_label() {
        case "$1" in
          actions) printf '%s' "actions" ;;
          files) printf '%s' "files" ;;
          stats) printf '%s' "statistics" ;;
          *) printf '%s' "$1" ;;
        esac
      }

      _actra_at_next_mode() {
        local line="${1-}"
        local count="${#ACTRA_AT_MODES[@]}"
        ACTRA_AT_MODE_INDEX=$(( (${ACTRA_AT_MODE_INDEX:--1} + 1) % count ))
        ACTRA_AT_MODE="${ACTRA_AT_MODES[$ACTRA_AT_MODE_INDEX]}"
        if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
          ACTRA_AT_ACTION_INDEX=-1
          _actra_at_load_action_candidates "$line"
          _actra_at_next_action
        else
          if [[ "$ACTRA_AT_MODE" == "stats" ]]; then
            ACTRA_AT_ACTION="stats"
            ACTRA_AT_ACTION_INDEX=-1
          else
            ACTRA_AT_ACTION=""
            ACTRA_AT_ACTION_INDEX=-1
          fi
        fi
      }

      _actra_at_prev_mode() {
        local line="${1-}"
        local count="${#ACTRA_AT_MODES[@]}"
        if (( ${ACTRA_AT_MODE_INDEX:--1} < 0 )); then
          ACTRA_AT_MODE_INDEX=$(( count - 1 ))
        else
          ACTRA_AT_MODE_INDEX=$(( (ACTRA_AT_MODE_INDEX + count - 1) % count ))
        fi
        ACTRA_AT_MODE="${ACTRA_AT_MODES[$ACTRA_AT_MODE_INDEX]}"
        if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
          ACTRA_AT_ACTION_INDEX=-1
          _actra_at_load_action_candidates "$line"
          _actra_at_prev_action
        else
          if [[ "$ACTRA_AT_MODE" == "stats" ]]; then
            ACTRA_AT_ACTION="stats"
            ACTRA_AT_ACTION_INDEX=-1
          else
            ACTRA_AT_ACTION=""
            ACTRA_AT_ACTION_INDEX=-1
          fi
        fi
      }

      _actra_at_mode_query() {
        local line="${1-}"
        local query="${line#@}"
        case "$query" in
          action) query="";;
          action" "*) query="${query#action }";;
          actions) query="";;
          actions" "*) query="${query#actions }";;
          *) query="$query";;
        esac
        query="${query# }"
        printf '%s' "$query"
      }

      _actra_at_action_query() {
        local line="${1-}"
        local query="${line#@}"
        case "$query" in
          action) query="";;
          action" "*) query="${query#action }";;
          actions) query="";;
          actions" "*) query="${query#actions }";;
          *) query="$query";;
        esac
        query="${query# }"
        printf '%s' "$query"
      }

      _actra_at_print_mode_picker() {
        local candidate label
        printf '\\n+------------------------------+\\\\n'
        printf '|         @ mode picker         |\\n'
        printf '+------------------------------+\\n'
        for candidate in "${ACTRA_AT_MODES[@]}"; do
          label="$(_actra_at_mode_label "$candidate")"
          if [[ "$candidate" == "$ACTRA_AT_MODE" ]]; then
            printf "| > %-27s |\\n" "$label"
          else
            printf "|   %-26s |\\n" "$label"
          fi
        done
        printf '+------------------------------+\\n'
      }

      _actra_at_render_preview() {
        printf '\e7'
        printf '\r'
        printf '\e[1E'
        printf '\r'
        printf '\e[0J'
      }

      _actra_at_show_mode_preview() {
        local query="$(_actra_at_mode_query "$READLINE_LINE")"
        local output
        if [[ "$ACTRA_AT_MODE" == "stats" ]]; then
          output="$(_actra_at_action_preview_cached "stats" "$query")"
        elif [[ "$ACTRA_AT_MODE" == "files" ]]; then
          output="$(_actra_at_file_preview_cached "$query")"
        else
          output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --mode-preview "$ACTRA_AT_MODE" "$query" 2>&1)"
        fi
        _actra_at_render_preview
        _actra_at_print_mode_picker
        [ -n "$output" ] && printf '%s\\n' "$output"
        printf '\e8'
      }

      _actra_at_show_action_preview() {
        local query="$(_actra_at_action_query "$READLINE_LINE")"
        _actra_at_load_action_candidates "$READLINE_LINE"
        local label
        local output
        output="$(_actra_at_action_preview_cached "$ACTRA_AT_ACTION" "$query")"
        _actra_at_render_preview
        _actra_at_print_mode_picker
        for candidate in "${ACTRA_AT_ACTIONS[@]}"; do
          label="$(_actra_at_action_label "$candidate")"
          if [[ "$candidate" == "$ACTRA_AT_ACTION" ]]; then
            printf "| > %-27s |\\n" "$label"
          else
            printf "|   %-26s |\\n" "$label"
          fi
        done
        printf '+------------------------------+\\n'
        [ -n "$output" ] && printf '%s\\n' "$output"
        printf '\e8'
      }

      _actra_at_tab_action() {
        if _actra_at_action_mode "$READLINE_LINE"; then
          _actra_at_load_action_candidates "$READLINE_LINE"
          _actra_at_next_action
          _actra_at_show_action_preview
        elif _actra_at_mode_mode "$READLINE_LINE"; then
          _actra_at_next_mode "$READLINE_LINE"
          if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
            _actra_at_show_action_preview
          else
            _actra_at_show_mode_preview
          fi
        else
          local before="${READLINE_LINE:0:READLINE_POINT}"
          local after="${READLINE_LINE:READLINE_POINT}"
          READLINE_LINE="${before}\t${after}"
          READLINE_POINT=$(( READLINE_POINT + 1 ))
        fi
      }

      _actra_at_shift_tab_action() {
        if _actra_at_action_mode "$READLINE_LINE"; then
          _actra_at_load_action_candidates "$READLINE_LINE"
          _actra_at_prev_action
          _actra_at_show_action_preview
        elif _actra_at_mode_mode "$READLINE_LINE"; then
          _actra_at_prev_mode "$READLINE_LINE"
          if [[ "$ACTRA_AT_MODE" == "actions" ]]; then
            _actra_at_show_action_preview
          else
            _actra_at_show_mode_preview
          fi
        else
          :
        fi
      }

      _actra_at_down_action() {
        if _actra_at_action_mode "$READLINE_LINE" || (_actra_at_mode_mode "$READLINE_LINE" && [[ "$ACTRA_AT_MODE" == "actions" ]]); then
          _actra_at_load_action_candidates "$READLINE_LINE"
          _actra_at_next_action
          _actra_at_show_action_preview
        else
          :
        fi
      }

      _actra_at_up_action() {
        if _actra_at_action_mode "$READLINE_LINE" || (_actra_at_mode_mode "$READLINE_LINE" && [[ "$ACTRA_AT_MODE" == "actions" ]]); then
          _actra_at_load_action_candidates "$READLINE_LINE"
          _actra_at_prev_action
          _actra_at_show_action_preview
        else
          :
        fi
      }

      _actra_at_j_action() {
        if _actra_at_action_mode "$READLINE_LINE" || (_actra_at_mode_mode "$READLINE_LINE" && [[ "$ACTRA_AT_MODE" == "actions" ]]); then
          _actra_at_load_action_candidates "$READLINE_LINE"
          _actra_at_next_action
          _actra_at_show_action_preview
        else
          local before="${READLINE_LINE:0:READLINE_POINT}"
          local after="${READLINE_LINE:READLINE_POINT}"
          READLINE_LINE="${before}j${after}"
          READLINE_POINT=$(( READLINE_POINT + 1 ))
        fi
      }

      _actra_at_k_action() {
        if _actra_at_action_mode "$READLINE_LINE" || (_actra_at_mode_mode "$READLINE_LINE" && [[ "$ACTRA_AT_MODE" == "actions" ]]); then
          _actra_at_load_action_candidates "$READLINE_LINE"
          _actra_at_prev_action
          _actra_at_show_action_preview
        else
          local before="${READLINE_LINE:0:READLINE_POINT}"
          local after="${READLINE_LINE:READLINE_POINT}"
          READLINE_LINE="${before}k${after}"
          READLINE_POINT=$(( READLINE_POINT + 1 ))
        fi
      }
      bind -x '"\\C-i": _actra_at_tab_action'
      bind -x '"\\e[Z": _actra_at_shift_tab_action'
      bind -x '"\\e[A": _actra_at_up_action'
      bind -x '"\\e[B": _actra_at_down_action'
      bind -x '"j": _actra_at_j_action'
      bind -x '"k": _actra_at_k_action'

      function @ {
        local action="${ACTRA_AT_ACTION:-}"
        local output exit_status
        ACTRA_AT_ACTION=""
        ACTRA_AT_ACTION_INDEX=-1
        ACTRA_AT_MODE=""
        ACTRA_AT_MODE_INDEX=-1
        ACTRA_AT_ACTION_QUERY_CACHE=""
        ACTRA_AT_ACTION_CANDIDATES_LOADED=0
        ACTRA_AT_ACTION_PREVIEW_CACHE_KEY=""
        ACTRA_AT_ACTION_PREVIEW_CACHE_VALUE=""
        ACTRA_AT_FILE_PREVIEW_CACHE_KEY=""
        ACTRA_AT_FILE_PREVIEW_CACHE_VALUE=""
        case "$action" in
          code|assistant|agent|run|background|remote|container|stats) output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ --action "$action" "$@")"; exit_status=$? ;;
          *)
            if [ -n "$action" ]; then
              output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ "$action" "$@")"; exit_status=$?
            else
              output="$(ACTRA_SHELL_HOOK=1 command #{binary} @ "$@")"; exit_status=$?
            fi
            ;;
        esac
        case "$output" in
          __ACTRA_INSERT__*)
            local insert="${output#__ACTRA_INSERT__}"
            if [ -n "${READLINE_LINE+x}" ]; then
              READLINE_LINE="${READLINE_LINE:0:READLINE_POINT}${insert}${READLINE_LINE:READLINE_POINT}"
              READLINE_POINT=$((READLINE_POINT + ${#insert}))
            else
              printf '%s\n' "$insert"
            fi
            ;;
          __ACTRA_CD__*)
            cd -- "${output#__ACTRA_CD__}"
            ;;
          *)
            [ -n "$output" ] && printf '%s\n' "$output"
            ;;
        esac
        return "$exit_status"
      }
      alias @code='_actra_dispatch @code'
      alias @assistant='actra @ --action assistant'
      alias @agent='actra @ --action agent'
      alias @run='actra @ --action run'
      alias @background='actra @ --action background'
      alias @remote='actra @ --action remote'
      alias @container='actra @ --action container'
      alias @stats='actra @ --action stats'
      alias @plan='_actra_dispatch @plan'
      alias @claude='_actra_dispatch @claude'
      alias @codex='_actra_dispatch @codex'

      _actra_complete_at() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        mapfile -t COMPREPLY < <(command #{binary} complete at "$cur" 2>/dev/null)
      }

      _actra_register_completions() {
        complete -F _actra_complete_at #{binary} @
        local cmd
        while IFS= read -r cmd; do
          [ -n "$cmd" ] && complete -F _actra_complete_at "$cmd"
        done < <(command #{binary} complete actors 2>/dev/null)
      }
      _actra_register_completions

      command_not_found_handle() {
        case "$1" in
          @) command #{binary} @ "${@:2}" ;;
          @\\?) return 127 ;;
          \\?*) _actra_query "$@" ;;
          @*) _actra_dispatch "$@" ;;
          *) return 127 ;;
        esac
      }
      BASH
    end
  end
end
