ANYENV_VERSION=""
ANYENV_FILENAME=".anyenv.sh"

anyenv_collect_scripts() {
	local path="$1"

	if [[ -z "$path" ]]; then
		return
	fi

	local file
	local current="$path"
	while true; do
		file="$current/$ANYENV_FILENAME"

		if [[ -r "$file" ]]; then
			echo "$file"
		fi

		if [[ "$current" == "/" ]]; then
			break
		else
			current="$(dirname "$current")"
		fi
	done
}

anyenv_run() {
	local op="$1"
	local script="$2"

	local verb
	case "$op" in
		(load)
			verb="Entering"
			;;
		(unload)
			verb="Leaving"
			;;
	esac

	local dir="$(dirname "$script")"
	echo "AnyEnv: $verb $dir"

	pushd "$dir" > /dev/null
	source "$script"
	[[ -n "type -t anyenv_$op" ]] && anyenv_$op
	popd > /dev/null
}

anyenv_hook() {
	if [[ -z "$ANYENV_LAST_DIR" ]]; then
		export ANYENV_LAST_DIR="$PWD"

		local in_scripts="$(anyenv_collect_scripts "$ANYENV_LAST_DIR" | sort)"
		if [[ -n "$in_scripts" ]]; then
			local in_script
			for in_script in "$in_scripts"; do
				if [[ -n "$in_script" ]]; then
					anyenv_run load "$in_script"
				fi
			done
		fi
	fi

	if [[ "$PWD" != "$ANYENV_LAST_DIR" ]]; then
		local in_scripts="$(anyenv_collect_scripts "$PWD" | sort)"
		local out_scripts="$(anyenv_collect_scripts "$ANYENV_LAST_DIR" | sort -r)"

		local in_script
		local out_script

		local -i found

		if [[ -n "$in_scripts" ]]; then
			for in_script in "$in_scripts"; do
					found=0
					for out_script in "$out_scripts"; do
						if [[ "$in_script" == "$out_script" ]]; then
							found=1
							break
						fi
					done
					if [[ $found -eq 0 ]]; then
						anyenv_run load "$in_script"
					fi
			done
		fi

		if [[ -n "$out_scripts" ]]; then
			for out_script in "$out_scripts"; do
				found=0
				for in_script in "$in_scripts"; do
					if [[ "$out_script" == "$in_script" ]]; then
						found=1
						break
					fi
				done
				if [[ $found -eq 0 ]]; then
					anyenv_run unload "$out_script"
				fi
			done
		fi

		export ANYENV_LAST_DIR="$PWD"
	fi
}

if ! [[ "$PROMPT_COMMAND" =~ "anyenv_hook" ]]; then
	PROMPT_COMMAND="anyenv_hook; $PROMPT_COMMAND"
fi