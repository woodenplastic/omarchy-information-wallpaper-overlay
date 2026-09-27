# Information Wallpaper Overlay: the exit status of long terminal commands,
# for the tasks tile to show them passed or failed. Sourced from ~/.bashrc
# (scripts/shell-hook on). PS0 notes when a command starts, without starting
# a process; before the next prompt, a command that ran five seconds or
# longer gets a line in $XDG_RUNTIME_DIR/information-wallpaper-overlay/.

[[ $- == *i* && -n ${BASH_VERSION-} && -z ${__iwo_hooked-} ]] || return 0
__iwo_hooked=1
__iwo_file="${XDG_RUNTIME_DIR:-/tmp}/information-wallpaper-overlay/commands.jsonl"

__iwo_done() {
  local status=$?
  # Under starship, $? is gone by the time this runs; it keeps it here.
  [[ -n ${__iwo_starship-} ]] && status=${STARSHIP_CMD_STATUS:-$status}
  if [[ -n ${__iwo_start-} ]]; then
    if ((EPOCHSECONDS - __iwo_start >= 5)); then
      [[ -d ${__iwo_file%/*} ]] || mkdir -p "${__iwo_file%/*}"
      printf '{"shell":%d,"start":%d,"end":%d,"status":%d}\n' "$$" "$__iwo_start" "$EPOCHSECONDS" "$status" >>"$__iwo_file"
    fi
    unset __iwo_start
  fi
  return "$status"
}

# A zero-length slice of a set variable, to run the assignment and show
# nothing; bash skips it for an unset one.
__iwo_z=x
PS0='${__iwo_z:$((__iwo_start=EPOCHSECONDS,0)):0}'"${PS0-}"

# Starship runs what's in STARSHIP_PROMPT_COMMAND after its own; in front of
# its PROMPT_COMMAND it would lose its timing.
if [[ ${PROMPT_COMMAND-} == *starship_precmd* ]]; then
  __iwo_starship=1
  STARSHIP_PROMPT_COMMAND="__iwo_done${STARSHIP_PROMPT_COMMAND:+;$STARSHIP_PROMPT_COMMAND}"
elif [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a"* ]]; then
  PROMPT_COMMAND=(__iwo_done "${PROMPT_COMMAND[@]}")
else
  PROMPT_COMMAND="__iwo_done${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
