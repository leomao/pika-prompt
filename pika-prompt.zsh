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
[[ -z "${PROMPT_COLOR_VENV}" ]] && PROMPT_COLOR_VENV=87
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
[[ -z "${PROMPT_COLOR_VIMVIS}" ]] && PROMPT_COLOR_VIMVIS=214
[[ -z "${PROMPT_COLOR_VIMREP}" ]] && PROMPT_COLOR_VIMREP=203
[[ -z "${PROMPT_COLOR_VIMINS}" ]] && PROMPT_COLOR_VIMINS=119

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pika_human_time_to_var() {
	local human total_seconds=$1 var=$2
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
	typeset -g prompt_pika_cmd_exec_time=
	(( elapsed > ${PIKA_CMD_MAX_EXEC_TIME:-5} )) && {
		prompt_pika_human_time_to_var $elapsed "prompt_pika_cmd_exec_time"
	}
}

prompt_pika_set_title() {
	# emacs terminal does not support settings the title
	(( ${+EMACS} )) && return

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
	if [[ -n $prompt_pika_git_fetch_pattern ]]; then
		# detect when git is performing pull/fetch (including git aliases).
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_pika_git_fetch_pattern)(\ .*)?$ ]]; then
			# we must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt_pika'
		fi
	fi

	typeset -g prompt_pika_cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title while a process is active
	prompt_pika_set_title 'ignore-escape' "$PWD:t: $2"
}

prompt_pika_truncate_pwd() {
	# n = number of directories to show in full (n = 3, /a/b/c/dee/ee/eff)
	local n=${PIKA_TRUNCATE_PWD_NUM:-4}
	local pwd_abbrev='%~'
	local pwd_path=${(S%%)pwd_abbrev}

	# split our path on /
	local pwd_dirs=("${(s:/:)pwd_path}")
	local dirs_length=$#pwd_dirs

	if [[ $dirs_length -ge $n ]]; then
		# we have more dirs than we want to show in full, so compact those down
		((max=dirs_length - n))
		for (( i = 1; i <= $max; i++ )); do
			step="$pwd_dirs[$i]"
			if [[ -z $step ]]; then
				continue
			fi
			if [[ $step =~ "^\." ]]; then
				pwd_dirs[$i]=$step[0,2] # .mydir => .m
			else
				pwd_dirs[$i]=$step[0,1] # mydir => m
			fi
		done
	fi

	print -n ${(j:/:)pwd_dirs}
}

prompt_pika_preprompt_render() {
	setopt localoptions noshwordsplit

	# Initialize the preprompt array.
	local -a preprompt_parts

	# if a virtualenv is activated, display it in grey
	if [[ -n $VIRTUAL_ENV ]]; then
		preprompt_parts+=("%F{$PROMPT_COLOR_VENV}(${VIRTUAL_ENV:t})%f")
	fi

	# Set the path.
	preprompt_parts+=("%F{$PROMPT_COLOR_PWD}"'$(prompt_pika_truncate_pwd)%f')

	# Add git branch and dirty status info.
	typeset -gA prompt_pika_vcs_info
	if [[ -n $prompt_pika_vcs_info[branch] ]]; then
		local git_status
		git_status="%F{$PROMPT_COLOR_GIT}"'${prompt_pika_vcs_info[branch]}%f'
		git_status+="%F{$PROMPT_COLOR_GIT_DIRTY}"'${prompt_pika_git_dirty}%f'
		# if dirty checking has been delayed.
		if [[ -n ${prompt_pika_git_last_dirty_check_timestamp+x} ]]; then
			git_status+="%F{$PROMPT_COLOR_GIT_DIRTY}?%f"
		fi

		preprompt_parts+=($git_status)
	fi
	# Git pull/push arrows.
	if [[ -n $prompt_pika_git_arrows ]]; then
		preprompt_parts+=("%F{$PROMPT_COLOR_GIT_ARROW}"'${prompt_pika_git_arrows}%f')
	fi

	# Username and machine, if applicable.
	[[ -n $prompt_pika_username ]] && preprompt_parts+=('$prompt_pika_username')
	# Execution time.
	if [[ -n $prompt_pika_cmd_exec_time ]]; then
		preprompt_parts+=("%F{$PROMPT_COLOR_EXECTIME}"'${prompt_pika_cmd_exec_time}%f')
	fi

	local cleaned_ps1=$PROMPT
	local -H MATCH MBEGIN MEND
	if [[ $PROMPT = *$prompt_newline* ]]; then
		# When the prompt contains newlines, we keep everything before the first
		# and after the last newline, leaving us with everything except the
		# preprompt. This is needed because some software prefixes the prompt
		# (e.g. virtualenv).
		cleaned_ps1=${PROMPT%%${prompt_newline}*}${PROMPT##*${prompt_newline}}
	fi
	unset MATCH MBEGIN MEND

	# Construct the new prompt with a clean preprompt.
	local -ah ps1
	ps1=(
		$prompt_newline           # Initial newline, for spaciousness.
		${(j. .)preprompt_parts}  # Join parts, space separated.
		$prompt_newline           # Separate preprompt and prompt.
		$cleaned_ps1
	)

	PROMPT="${(j..)ps1}"

	# Expand the prompt for future comparision.
	local expanded_prompt
	expanded_prompt="${(S%%)PROMPT}"

	if [[ $1 != precmd ]] && [[ $prompt_pika_last_prompt != $expanded_prompt ]]; then
		# Redraw the prompt.
		zle && zle .reset-prompt
	fi

	typeset -g prompt_pika_last_prompt=$expanded_prompt
}

prompt_pika_precmd() {
	# check exec time and store it in a variable
	prompt_pika_check_cmd_exec_time
	unset prompt_pika_cmd_timestamp

	# shows the full path in the title
	prompt_pika_set_title 'expand-prompt' '%~'

	# preform async git dirty check and fetch
	prompt_pika_async_tasks

	# print the preprompt
	prompt_pika_preprompt_render "precmd"
}

prompt_pika_async_git_aliases() {
	setopt localoptions noshwordsplit
	local dir=$1
	local -a gitalias pullalias

	# we enter repo to get local aliases as well.
	builtin cd -q $dir

	# list all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # split line on spaces
		aliasname=${parts[1]#alias.}  # grab the name (alias.[name])
		shift parts                   # remove aliasname

		# check alias for pull or fetch (must be exact match).
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # join on pipe (for use in regex).
}

prompt_pika_async_vcs_info() {
	setopt localoptions noshwordsplit
	builtin cd -q $1 2>/dev/null

	# configure vcs_info inside async task, this frees up vcs_info
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# only export two msg variables from vcs_info
	zstyle ':vcs_info:*' max-exports 2
	# export branch (%b) and git toplevel (%R)
	zstyle ':vcs_info:git*' formats '%b' '%R'
	zstyle ':vcs_info:git*' actionformats '%b|%a' '%R'

	vcs_info

	local -A info
	info[top]=$vcs_info_msg_1_
	info[branch]=$vcs_info_msg_0_

	print -r - ${(@kvq)info}
}

# fastest possible way to check if repo is dirty
prompt_pika_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1 dir=$2

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	if [[ $untracked_dirty = 0 ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	return $?
}

prompt_pika_async_git_fetch() {
	setopt localoptions noshwordsplit
	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $1

	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
	export GIT_TERMINAL_PROMPT=0
	# set ssh BachMode to disable all interactive ssh password prompting
	export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes"}

	command git -c gc.auto=0 fetch &>/dev/null || return 99

	# check arrow status after a successful git fetch
	prompt_pika_async_git_arrows $1
}

prompt_pika_async_git_arrows() {
	setopt localoptions noshwordsplit
	builtin cd -q $1
	command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_pika_async_tasks() {
	setopt localoptions noshwordsplit

	# initialize async worker
	((!${prompt_pika_async_init:-0})) && {
		async_start_worker "prompt_pika" -u -n
		async_register_callback "prompt_pika" prompt_pika_async_callback
		typeset -g prompt_pika_async_init=1
	}

	typeset -gA prompt_pika_vcs_info

	local -H MATCH MBEGIN MEND
	if ! [[ $PWD = ${prompt_pika_vcs_info[pwd]}* ]]; then
		# stop any running async jobs
		async_flush_jobs "prompt_pika"

		# reset git preprompt variables, switching working tree
		unset prompt_pika_git_dirty
		unset prompt_pika_git_last_dirty_check_timestamp
		unset prompt_pika_git_arrows
		unset prompt_pika_git_fetch_pattern
		prompt_pika_vcs_info[branch]=
		prompt_pika_vcs_info[top]=
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_pika" prompt_pika_async_vcs_info $PWD

	# # only perform tasks inside git working tree
	[[ -n $prompt_pika_vcs_info[top] ]] || return

	prompt_pika_async_refresh
}

prompt_pika_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_pika_git_fetch_pattern ]]; then
		# we set the pattern here to avoid redoing the pattern check until the
		# working three has changed. pull and fetch are always valid patterns.
		typeset -g prompt_pika_git_fetch_pattern="pull|fetch"
		async_job "prompt_pika" prompt_pika_async_git_aliases $working_tree
	fi

	async_job "prompt_pika" prompt_pika_async_git_arrows $PWD

	# do not preform git fetch if it is disabled or working_tree == HOME
	if (( ${PIKA_GIT_PULL:-$pika_git_pull_default} )) && [[ $working_tree != $HOME ]]; then
		# tell worker to do a git fetch
		async_job "prompt_pika" prompt_pika_async_git_fetch $PWD
	fi

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_pika_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${PIKA_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_pika_git_last_dirty_check_timestamp
		# check check if there is anything to pull
		async_job "prompt_pika" prompt_pika_async_git_dirty ${PIKA_GIT_UNTRACKED_DIRTY:-1} $PWD
	fi
}

prompt_pika_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=${PIKA_GIT_DOWN_ARROW:-⇣}
	(( left > 0 )) && arrows+=${PIKA_GIT_UP_ARROW:-⇡}

	[[ -n $arrows ]] || return
	typeset -g REPLY=$arrows
}

prompt_pika_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	case $job in
		prompt_pika_async_vcs_info)
			local -A info
			typeset -gA prompt_pika_vcs_info

			# parse output (z) and unquote as array (Q@)
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			# check if git toplevel has changed
			if [[ $info[top] = $prompt_pika_vcs_info[top] ]]; then
				# if stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be toplevel, so we update pwd
				if [[ $prompt_pika_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_pika_vcs_info[pwd]=$PWD
				fi
			else
				# store $PWD to detect if we (maybe) left the git path
				prompt_pika_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# update has a git toplevel set which means we just entered a new
			# git directory, run the async refresh tasks
			[[ -n $info[top] ]] && [[ -z $prompt_pika_vcs_info[top] ]] && prompt_pika_async_refresh

			# always update branch and toplevel
			prompt_pika_vcs_info[branch]=$info[branch]
			prompt_pika_vcs_info[top]=$info[top]

			do_render=1
			;;
		prompt_pika_async_git_aliases)
			if [[ -n $output ]]; then
				# append custom git aliases to the predefined ones.
				prompt_pika_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_pika_async_git_dirty)
			local prev_dirty=$prompt_pika_git_dirty
			if (( code == 0 )); then
				unset prompt_pika_git_dirty
			else
				typeset -g prompt_pika_git_dirty=${PIKA_GIT_DIRTY:-"±"}
			fi

			[[ $prev_dirty != $prompt_pika_git_dirty ]] && do_render=1

			# When prompt_pika_git_last_dirty_check_timestamp is set, the git info is displayed in a different color.
			# To distinguish between a "fresh" and a "cached" result, the preprompt is rendered before setting this
			# variable. Thus, only upon next rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 5 )) && prompt_pika_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pika_async_git_fetch|prompt_pika_async_git_arrows)
			# prompt_pika_async_git_fetch executes prompt_pika_async_git_arrows
			# after a successful fetch.
			if (( code == 0 )); then
				local REPLY
				prompt_pika_check_git_arrows ${(ps:\t:)output}
				if [[ $prompt_pika_git_arrows != $REPLY ]]; then
					typeset -g prompt_pika_git_arrows=$REPLY
					do_render=1
				fi
			elif (( code != 99 )); then
				# Unless the exit code is 99, prompt_pika_async_git_arrows
				# failed with a non-zero exit status, meaning there is no
				# upstream configured.
				if [[ -n $prompt_pika_git_arrows ]]; then
					unset prompt_pika_git_arrows
					do_render=1
				fi
			fi
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_pika_async_render_requested=1
		return
	fi

	[[ ${prompt_pika_async_render_requested:-$do_render} = 1 ]] && prompt_pika_preprompt_render
	unset prompt_pika_async_render_requested
}

prompt_pika_setup() {
	# disallow python virtualenvs from updating the prompt
	export VIRTUAL_ENV_DISABLE_PROMPT=1

	prompt_opts=(subst percent)

	# borrowed from promptinit, sets the prompt options in case pika was not
	# initialized via promptinit.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pika_precmd
	add-zsh-hook preexec prompt_pika_preexec

	# show username@host if logged in through SSH
	if [[ "$SSH_CONNECTION" != '' ]]; then
		prompt_pika_username="%F{$PROMPT_COLOR_USER}%n%f"
		prompt_pika_username+="%F{$PROMPT_COLOR_AT}@%f"
		prompt_pika_username+="%F{$PROMPT_COLOR_HOST}%m%f"
	fi

	typeset -g pika_git_pull_default=0
	# show username@host if root, with username in white
	# Also disable auto fetching
	if [[ $UID -eq 0 ]]; then
		prompt_pika_username='%F{white}%n%f%F{242}@%m%f'
		typeset -g pika_git_pull_default=0
	fi

	typeset -g prompt_pika_mode
	if (( $+functions[add-vi-mode-hook] )); then
		vi-mode-info() {
			case $1 in
				"i")
					prompt_pika_mode="%B%F{$PROMPT_COLOR_VIMINS} I %f%b"
					;;
				"n")
					prompt_pika_mode="%B%F{$PROMPT_COLOR_VIMCMD} N %f%b"
					;;
				"v"|"V")
					prompt_pika_mode="%B%F{$PROMPT_COLOR_VIMVIS} V %f%b"
					;;
				"r")
					prompt_pika_mode="%B%F{$PROMPT_COLOR_VIMREP} R %f%b"
					;;
				*)
					prompt_pika_mode="%B $1 $2 %b"
					;;
			esac
			if [[ "$2" == 'keymap-select' ]]; then
				zle .reset-prompt
			fi
		}
		zle -N vi-mode-info
		add-vi-mode-hook vi-mode-info
	fi

	# prompt turns red if the previous command didn't exit with 0
	PROMPT='$prompt_pika_mode%(?.%F{$PROMPT_COLOR_SYMBOL}.%F{$PROMPT_COLOR_SYMBOL_E})${PIKA_PROMPT_SYMBOL:-❯}%f '

	# register custom reset-prompt
	reset-prompt() {
		prompt_pika_precmd
		zle .reset-prompt
	}
	zle -N reset-prompt
}

prompt_pika_setup "$@"

# vim: set noet:
