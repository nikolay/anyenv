readonly ANYENV_VERSION=""
readonly ANYENV_FILENAME=".anyenv.sh"
readonly ANYENV_HOME="${HOME}/.anyenv"

anyenv () {
	# cleanup

	AnyEnv::cleanup () {
		if [[ ${FUNCNAME[1]} == "anyenv" && ${FUNCNAME[2]} != "anyenv" ]]; then
			trap "unset -f $(typeset -F | cut -d ' ' -f 3 | grep '^AnyEnv::' | tr '\n' ' ' | xargs) && trap - RETURN" RETURN
		fi
	}

	trap "$(typeset -f AnyEnv::cleanup) && AnyEnv::cleanup" RETURN

	# constants

	local -ri SIGNATURE_ALGORITHM=256
	local -r SIGNATURE_DIR="${ANYENV_HOME}/signatures"

	# colors

	local bold underline standout normal black red green yellow blue magenta cyan white
	if [[ -t 1 ]]; then
		local -ri number_of_colors="$(tput colors)"
		# shellcheck disable=SC2034
		if (( number_of_colors >= 8 )); then
			bold="$(tput bold)"
			underline="$(tput smul)"
			standout="$(tput smso)"
			normal="$(tput sgr0)"
			black="$(tput setaf 0)"
			red="$(tput setaf 1)"
			green="$(tput setaf 2)"
			yellow="$(tput setaf 3)"
			blue="$(tput setaf 4)"
			magenta="$(tput setaf 5)"
			cyan="$(tput setaf 6)"
			white="$(tput setaf 7)"
		fi
	fi

	# logging

	AnyEnv::log () {
		printf "%s\n" "$*"
	}

	AnyEnv::note () {
		AnyEnv::log "${green}[NOTE]${normal} $*"
	}

	AnyEnv::err () {
		AnyEnv::log "${red}[ERR]${normal} $*" >&2
	}

	AnyEnv::fatal () {
		AnyEnv::err "$@"
		exit 1
	}

	# signatures

	AnyEnv::Signatures::calculate () {
		local -r file="$1"
		shasum -a ${SIGNATURE_ALGORITHM} "${file}" | shasum -a ${SIGNATURE_ALGORITHM} | cut -d ' ' -f 1
	}

	AnyEnv::Signatures::verify () {
		local -r file="$1"

		local -r signature="$(anyenv calculate-signature "${file}")"

		[[ -r "${SIGNATURE_DIR}/${signature}" ]]
	}

	AnyEnv::Signatures::clear_all () {
		rm -f "${SIGNATURE_DIR}"/*
		AnyEnv::note "All signatured cleared"
	}

	AnyEnv::Signatures::sign () {
		local -r file="$1"

		if [[ -r "${file}" ]]; then
			local -r signature="$(anyenv calculate-signature "${file}")"

			mkdir -p "${SIGNATURE_DIR}"
			touch "${SIGNATURE_DIR}/${signature}"

			AnyEnv::note "Signed: ${bold}${file}${normal}"

			# fire the sign hook

			echo "Testing..."

			local -a in_scripts
			mapfile -t in_scripts < <(AnyEnv::Hook::collect_scripts "$(dirname "${file}")" | sort)

			if (( ${#in_scripts[@]} )); then
				local in_script
				for in_script in "${in_scripts[@]}"; do
					AnyEnv::Hook::run_script sign "${in_script}"
				done
			fi
		else
			AnyEnv::fatal "Cannot read ${bold}${file}${normal}"
		fi
	}

	# hook

	AnyEnv::Hook::collect_scripts () {
		local -r path="$1"

		if [[ -n "${path}" ]]; then
			local file
			local current="${path}"
			while true; do
				file="${current}/${ANYENV_FILENAME}"
				if [[ -r "${file}" ]]; then
					echo "${file}"
				fi
				if [[ ${current} == '/' ]]; then
					break
				fi
				current="$(dirname "${current}")"
			done
		fi
	}

	AnyEnv::Hook::run_script () {
		local -r op="$1"
		local -r script="$2"

		local -r dir="$(dirname "${script}")"

		if anyenv verify-signature "${script}"; then
			pushd "${dir}" > /dev/null

			# shellcheck disable=SC1090
			source "${script}"

			if [[ -n "$(type -t "anyenv_${op}")" ]]; then
				"anyenv_${op}"
			fi

			popd > /dev/null
		else
			AnyEnv::note "Sign using: ${bold}anyenv sign ${script}${normal}"
		fi
	}

	AnyEnv::Hook::handler () {
		if [[ -z "${ANYENV_LAST_DIR}" ]]; then
			local -a in_scripts
			mapfile -t in_scripts < <(AnyEnv::Hook::collect_scripts "${PWD}" | sort)

			if (( ${#in_scripts[@]} )); then
				local in_script
				for in_script in "${in_scripts[@]}"; do
					AnyEnv::Hook::run_script load "${in_script}"
				done
			fi
		elif [[ ${PWD} != "${ANYENV_LAST_DIR}" ]]; then
			local -a in_scripts
			mapfile -t in_scripts < <(AnyEnv::Hook::collect_scripts "${PWD}" | sort)

			local -a out_scripts
			mapfile -t out_scripts < <(AnyEnv::Hook::collect_scripts "${ANYENV_LAST_DIR}" | sort -r)

			local in_script
			local out_script

			local -i found

			if (( ${#in_scripts[@]} )); then
				for in_script in "${in_scripts[@]}"; do
					found=0
					for out_script in "${out_scripts[@]}"; do
						if [[ ${in_script} == "${out_script}" ]]; then
							found=1
							break
						fi
					done
					if (( ! found )); then
						AnyEnv::Hook::run_script load "${in_script}"
					fi
				done
			fi

			if (( ${#out_scripts[@]} )); then
				for out_script in "${out_scripts[@]}"; do
					found=0
					for in_script in "${in_scripts[@]}"; do
						if [[ ${out_script} == "${in_script}" ]]; then
							found=1
							break
						fi
					done
					if (( ! found )); then
						AnyEnv::Hook::run_script unload "${out_script}"
					fi
				done
			fi
		fi

		export ANYENV_LAST_DIR="${PWD}"
	}

	# help

	AnyEnv::usage () {
		cat <<-"EOF"
			Usage: anyenv <command> [<parameter>...]

			Commands:
			  sign [<script>...]   Signs the scripts specified or the current one
			  clear-signatures     Clears all script signatures
			  help                 Show usage
		EOF
	}

	# main

	local -r command="$1" && shift

	case "${command}" in
		init)
			local -r hook="anyenv hook;"
			if [[ ! ${PROMPT_COMMAND} =~ ${hook} ]]; then
				export PROMPT_COMMAND="${hook} ${PROMPT_COMMAND}"
			fi
			;;

		hook)
			AnyEnv::Hook::handler
			;;

		calculate-signature)
			local -r file="$1"
			AnyEnv::Signatures::calculate "${file}"
			;;

		verify-signature)
			local -r file="$1"
			AnyEnv::Signatures::verify "${file}"
			;;

		clear-signatures)
			AnyEnv::Signatures::clear_all
			;;

		sign)
			if (( $# )); then
				local file
				for file; do
					AnyEnv::Signatures::sign "${file}"
				done
			else
				local -r file="${ANYENV_LAST_DIR}/${ANYENV_FILENAME}"
				AnyEnv::Signatures::sign "${file}"
			fi

			ANYENV_LAST_DIR="$(dirname "${PWD}")" anyenv hook
			;;

		help|*)
			AnyEnv::usage
			;;
	esac

}

if [[ ${BASH_SOURCE} == "$0" ]]; then
	anyenv "$@"
else
	anyenv init
fi
