# pika prompt
# Author: LeoMao
# https://github.com/leomao/pika-prompt
# Modified from pure: https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# default color settings
[[ -z "${PROMPT_COLOR_PWD}" ]] && PROMPT_COLOR_PWD=blue
[[ -z "${PROMPT_COLOR_GIT}" ]] && PROMPT_COLOR_GIT=242
[[ -z "${PROMPT_COLOR_GIT_DIRTY}" ]] && PROMPT_COLOR_GIT_DIRTY=red
[[ -z "${PROMPT_COLOR_GIT_ARROW}" ]] && PROMPT_COLOR_GIT_ARROW=cyan
[[ -z "${PROMPT_COLOR_EXECTIME}" ]] && PROMPT_COLOR_EXECTIME=yellow
[[ -z "${PROMPT_COLOR_USER}" ]] && PROMPT_COLOR_USER=242
[[ -z "${PROMPT_COLOR_ROOT}" ]] && PROMPT_COLOR_ROOT=white
[[ -z "${PROMPT_COLOR_AT}" ]] && PROMPT_COLOR_AT=242
[[ -z "${PROMPT_COLOR_HOST}" ]] && PROMPT_COLOR_HOST=242
[[ -z "${PROMPT_COLOR_SYMBOL}" ]] && PROMPT_COLOR_SYMBOL=magenta
[[ -z "${PROMPT_COLOR_SYMBOL_E}" ]] && PROMPT_COLOR_SYMBOL_E=red
[[ -z "${PROMPT_COLOR_VIMCMD}" ]] && PROMPT_COLOR_VIMCMD=69
[[ -z "${PROMPT_COLOR_VIMINS}" ]] && PROMPT_COLOR_VIMINS=119
[[ -z "${PROMPT_COLOR_VIMVIS}" ]] && PROMPT_COLOR_VIMVIS=214
[[ -z "${PROMPT_COLOR_VIMREP}" ]] && PROMPT_COLOR_VIMREP=203

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pika_human_time_to_var() {
	local human=" " total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# store human readable time in variable as specified by caller
	typeset -g "${var}"="${human}"
}

# stores (into prompt_pika_cmd_exec_time) the exec time of the last command if set threshold was exceeded
prompt_pika_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_pika_cmd_timestamp:-$EPOCHSECONDS} ))
	prompt_pika_cmd_exec_time=
	(( elapsed > ${PIKA_CMD_MAX_EXEC_TIME:=5} )) && {
		prompt_pika_human_time_to_var $elapsed "prompt_pika_cmd_exec_time"
	}
}

prompt_pika_check_git_arrows() {
	# reset git arrows
	prompt_pika_git_arrows=

	[[ -n $working_tree ]] || return

	# check if there is an upstream configured for this branch
	command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

	local arrow_status
	# check git left and right arrow_status
	arrow_status="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"
	# exit if the command failed
	(( !$? )) || return

	# left and right are tab-separated, split on tab and store as array
	arrow_status=(${(ps:\t:)arrow_status})
	local arrows left=${arrow_status[1]} right=${arrow_status[2]}

	(( ${right:-0} > 0 )) && arrows+="${PIKA_GIT_DOWN_ARROW:-⇣}"
	(( ${left:-0} > 0 )) && arrows+="${PIKA_GIT_UP_ARROW:-⇡}"

	[[ -n $arrows ]] && prompt_pika_git_arrows=" ${arrows}"

	if (( ${prompt_pika_git_fetching} )); then
		prompt_pika_git_arrows+=" ${PIKA_GIT_FETCH_SYMBOL:-↻ }"
	fi
}

prompt_pika_set_title() {
	# tell the terminal we are setting the title
	print -n '\e]0;'
	# show hostname if connected through ssh
	[[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
	case $1 in
		expand-prompt)
			print -Pn $2;;
		ignore-escape)
			print -rn $2;;
	esac
	# end set title
	print -n '\a'
}

prompt_pika_preexec() {
	prompt_pika_cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title while a process is active
	prompt_pika_set_title 'ignore-escape' "$PWD:t: $2"
}

# string length ignoring ansi escapes
prompt_pika_string_length_to_var() {
	local str=$1 var=$2 length
	# perform expansion on str and check length
	length=$(( ${#${(S%%)str//(\%([KF1]|)\{*\}|\%[Bbkf])}} ))

	# store string length in variable as specified by caller
	typeset -g "${var}"="${length}"
}

prompt_pika_update_prompt() {
	# check that no command is currently running, the preprompt will otherwise be rendered in the wrong place
  #[[ -n ${prompt_pika_cmd_timestamp+x} && "$1" != "precmd" ]] && return

	# construct preprompt, beginning with path
	preprompt="%F{$PROMPT_COLOR_PWD}%~%f"
	# git info
  preprompt+="%F{$PROMPT_COLOR_GIT}${vcs_info_msg_0_}%f"
  preprompt+="%F{$PROMPT_COLOR_GIT_DIRTY}${prompt_pika_git_dirty}${prompt_pika_git_dirty_checking}%f"
	# git pull/push arrows
	preprompt+="%F{$PROMPT_COLOR_GIT_ARROW}${prompt_pika_git_arrows}%f"
	# username and machine if applicable
	preprompt+=$prompt_pika_username
	# execution time
	preprompt+="%F{$PROMPT_COLOR_EXECTIME}${prompt_pika_cmd_exec_time}%f"

	# perform fancy terminal editing only for update
  if [[ "$1" != "precmd" ]]; then
    # only redraw if preprompt has changed
    [[ "${prompt_pika_last_preprompt}" != "${preprompt}" ]] || return

    prompt_pika_setup_prompt
    zle && zle .reset-prompt
  fi

	# store previous preprompt for comparison
	prompt_pika_last_preprompt=$preprompt
}

prompt_pika_precmd() {
	# check exec time and store it in a variable
	prompt_pika_check_cmd_exec_time

	# check for git arrows
	prompt_pika_check_git_arrows

	# shows the full path in the title
	prompt_pika_set_title 'expand-prompt' '%~'

	# get vcs info
  vcs_info

	# preform async git dirty check and fetch
	prompt_pika_async_tasks

	# print the preprompt
	prompt_pika_update_prompt
}

# fastest possible way to check if repo is dirty
prompt_pika_async_git_dirty() {
	local untracked_dirty=$1; shift

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q "$*"

	if [[ "$untracked_dirty" == "0" ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	(( $? )) && echo ${PIKA_GIT_DIRTY:-"±"}
}

prompt_pika_async_git_fetch() {
	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q "$*"

	# disable auth prompting for git fetch (git 2.3+)
	SSH_ASKPASS=0 GIT_TERMINAL_PROMPT=0 command git -c gc.auto=0 fetch
}

prompt_pika_async_tasks() {
	# initialize async worker
	if ((!${prompt_pika_async_init:-0})); then
		async_start_worker "prompt_pika" -u -n
		async_register_callback "prompt_pika" prompt_pika_async_callback
		prompt_pika_async_init=1
	fi

	# store working_tree without the "x" prefix
	local working_tree="${vcs_info_msg_1_#x}"

	# check if the working tree changed (prompt_pika_current_working_tree is prefixed by "x")
	if [[ ${prompt_pika_current_working_tree#x} != $working_tree ]]; then
		# stop any running async jobs
		async_flush_jobs "prompt_pika"

		# reset git preprompt variables, switching working tree
		unset prompt_pika_git_dirty
		unset prompt_pika_git_dirty_checking
		unset prompt_pika_git_fetching

		# set the new working tree and prefix with "x" to prevent the creation of a named path by AUTO_NAME_DIRS
		prompt_pika_current_working_tree="x${working_tree}"

		# do not preform git fetch if it is disabled or working_tree == HOME
		if (( ${PIKA_GIT_FETCH:-1} )) && [[ -n $working_tree ]]; then
			# tell worker to do a git fetch
			prompt_pika_git_fetching=1
			async_job "prompt_pika" prompt_pika_async_git_fetch "${working_tree}"
		fi
	fi

	prompt_pika_check_git_arrows
	prompt_pika_update_prompt

	# only perform tasks inside git working tree
	[[ -n $working_tree ]] || return

  if ! [[ -n ${prompt_pika_git_dirty_checking} ]]; then
    prompt_pika_git_dirty_checking="?"
    async_job "prompt_pika" prompt_pika_async_git_dirty "${PIKA_GIT_UNTRACKED_DIRTY:-1}" "${working_tree}"
  fi
}

prompt_pika_async_callback() {
	local job=$1
	local output=$3
	local exec_time=$4

	case "${job}" in
		prompt_pika_async_git_dirty)
			unset prompt_pika_git_dirty_checking
			prompt_pika_git_dirty=$output
			prompt_pika_update_prompt
			;;
		prompt_pika_async_git_fetch)
			unset prompt_pika_git_fetching
			prompt_pika_check_git_arrows
			prompt_pika_update_prompt
			;;
	esac
}

prompt_pika_setup_prompt() {
  PROMPT="$terminfo[cud1]"
  PROMPT+="$preprompt$terminfo[cud1]"
	# prompt turns red if the previous command didn't exit with 0
  PROMPT+=" $prompt_mode %(?.%F{$PROMPT_COLOR_SYMBOL}.%F{$PROMPT_COLOR_SYMBOL_E})${PIKA_PROMPT_SYMBOL:-❯}%f "
}

prompt_pika_setup() {
	prompt_opts=(subst percent)

	zmodload zsh/datetime
	zmodload zsh/zle
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pika_precmd
	add-zsh-hook preexec prompt_pika_preexec

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# only export two msg variables from vcs_info
	zstyle ':vcs_info:*' max-exports 2
	# vcs_info_msg_0_ = ' %b' (for branch)
	# vcs_info_msg_1_ = 'x%R' git top level (%R), x-prefix prevents creation of a named path (AUTO_NAME_DIRS)
	zstyle ':vcs_info:git*' formats ' %b' 'x%R'
	zstyle ':vcs_info:git*' actionformats ' %b|%a' 'x%R'

	# show username@host if logged in through SSH
	if [[ "$SSH_CONNECTION" != '' ]]; then
		prompt_pika_username=" %F{$PROMPT_COLOR_USER}%n%f"
		prompt_pika_username+="%F{$PROMPT_COLOR_AT}@%f"
		prompt_pika_username+="%F{$PROMPT_COLOR_HOST}%m%f"
	fi

	# show username@host if root, with username in white
	[[ $UID -eq 0 ]] && prompt_pika_username=' %F{white}%n%f%F{242}@%m%f'

	prompt_pika_setup_prompt
	if (( $+functions[add-vi-mode-hook] )); then
		vi-mode-info() {
			case $1 in
				"i")
					prompt_mode="%B%F{$PROMPT_COLOR_VIMINS}I%f%b"
					;;
				"n")
					prompt_mode="%B%F{$PROMPT_COLOR_VIMCMD}N%f%b"
					;;
				"v"|"V")
					prompt_mode="%B%F{$PROMPT_COLOR_VIMVIS}V%f%b"
					;;
				"r")
					prompt_mode="%B%F{$PROMPT_COLOR_VIMREP}R%f%b"
					;;
			esac
			prompt_pika_setup_prompt
			zle .reset-prompt
		}
		zle -N vi-mode-info
		add-vi-mode-hook vi-mode-info
	fi
}

prompt_pika_setup "$@"

# vim: set noet:
