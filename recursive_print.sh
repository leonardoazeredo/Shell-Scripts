#!/usr/bin/env bash
#
# file-crawler.sh - High-performance, parallel file crawler with progress bar.
# Version 5.1: Fixed POSIX compatibility bug and enhanced comments for education.

# This is the "unofficial strict mode" for Bash scripts. It's a best practice.
# -e: Exit immediately if any command fails. This prevents errors from being ignored.
# -u: Treat unset (un-assigned) variables as an error. This catches typos.
# -o pipefail: If a command in a pipeline (e.g., `find | wc`) fails, the whole
#              pipeline's exit code reflects that failure.
set -euo pipefail

################################################################################
# SCRIPT FUNCTIONS
################################################################################

#
# This function prints the usage instructions.
# It cleverly extracts the comment block from the top of this script file.
# - `awk` is a text-processing tool. Here, it finds the line starting with
#   "# USAGE:" or "# EXAMPLES:", prints it with color, and then sets a `flag`.
#   It continues printing every line while `flag` is set, until it sees the
#   end marker (`# ##`), making the help text easy to maintain.
# - `sed` then cleans up the leading comment characters ('# ') for clean output.
#
print_help() {
    # Setup colors for the help text, but only if the terminal supports it.
    local C_USAGE="" C_EXAMPLE="" C_RESET=""
    if [[ -t 1 ]]; then # Check if stdout (output stream 1) is a terminal
        C_USAGE=$(tput setaf 3)   # Yellow
        C_EXAMPLE=$(tput setaf 2) # Green
        C_RESET=$(tput sgr0)      # Reset color
    fi

    awk -v c_usage="$C_USAGE" -v c_example="$C_EXAMPLE" -v c_reset="$C_RESET" \
    '
    /^# USAGE:/{
        print c_usage $0 c_reset;
        flag=1; next
    }
    /^# EXAMPLES:/{
        print c_example $0 c_reset;
        flag=1; next
    }
    /^# ?#/{flag=0}
    flag' "$0" | sed -e 's/^# \?//' -e 's/^#//'
}

#
# A safe way to get the absolute path of a file or directory.
# Not all systems have the `realpath` command, so this function provides a fallback.
#
get_realpath() {
    # `command -v` checks if a command exists. We redirect its output (`&>`)
    # to `/dev/null` because we only care about its success or failure.
    if command -v realpath &>/dev/null; then
        # If `realpath` exists, use it. It's the best tool for the job.
        realpath "$1"
    else
        # *** FIX ***
        # This is the portable fallback for systems without `realpath`.
        # It runs commands in a subshell `()` to avoid changing the script's
        # current directory.
        # 1. `cd` into the directory of the path provided (`"$(dirname "$1")"`).
        # 2. `pwd -P` prints the physical working directory (resolving symlinks).
        # 3. We capture this directory path in a variable.
        local dir
        dir=$(cd "$(dirname "$1")" && pwd -P)
        # 4. We construct the full, absolute path and print it.
        echo "${dir}/$(basename "$1")"
    fi
}

#
# This function runs as a background process to draw and update the progress bar.
# It works by periodically checking how many result files have been created in the
# temporary directory by the parallel worker processes.
#
# Arguments:
#   $1: The Process ID (PID) of the main script. The updater stops if the main script exits.
#   $2: The temporary directory to monitor for new files.
#   $3: The total number of files we expect, to calculate the percentage.
#
progress_bar_updater() {
    local parent_pid="$1" temp_dir="$2" total_files="$3"
    local bar_length=40

    [[ "$total_files" -eq 0 ]] && return

    # `ps -p` checks if a process with a given PID is running.
    while ps -p "$parent_pid" > /dev/null; do
        local current_count
        current_count=$(find "$temp_dir" -type f | wc -l)
        
        (( current_count > total_files )) && current_count=$total_files

        local progress=$((current_count * 100 / total_files))
        local filled=$((progress * bar_length / 100))
        local bar

        # `printf -v bar` stores the output in the variable `bar` instead of printing it.
        # `${bar// /#}` is parameter expansion to replace all spaces with '#'.
        printf -v bar '%*s' "$filled" '' && bar=${bar// /#}
        printf -v bar '%-*s' "$bar_length" "$bar" && bar=${bar// /-}

        # `\r` moves the cursor to the line's start, creating an animation.
        printf "\r[%s] %d%% (%d/%d files)" "$bar" "$progress" "$current_count" "$total_files" >&2
        
        [[ "$current_count" -eq "$total_files" ]] && break
        sleep 0.1 # Pause briefly to avoid wasting CPU cycles.
    done
}


#
# This is the "worker" function. It processes a single file.
# `xargs` will run many instances of this function in parallel.
#
process_file_parallel() {
    local file="$1"
    local temp_dir="$2"

    # `${file##*/}` removes the longest prefix `*/`, giving the filename.
    local filename="${file##*/}"
    # `${filename##*.}` removes the longest prefix `*.`, giving the extension.
    local extension="${filename##*.}"
    [[ "$extension" == "$filename" ]] && extension="text"

    local display_path
    if [[ "$file" == "$BASE_CWD"/* ]]; then
        display_path="${CWD_BASE_NAME}/${file#$BASE_CWD/}"
    else
        display_path="$file"
    fi

    # `mktemp` creates a unique temporary file. This is critical to prevent
    # parallel processes from writing to the same file at once.
    local temp_output
    temp_output=$(mktemp "${temp_dir}/output.XXXXXXXXXX")

    # Using a `{...}` group is slightly more efficient than multiple `>>` appends.
    {
        printf '```%s\n' "$extension"
        printf '// %s\n' "$display_path"
        cat -- "$file" # Append the actual file content.
        printf '\n```\n\n'
    } > "$temp_output"
}
# `export -f` makes the function available to subshells, which `xargs` creates.
# We also export the global path variables so the function can use them.
export -f process_file_parallel
export BASE_CWD CWD_BASE_NAME

#
# The main function where the script's execution begins.
#
main() {
    # --- Configuration and Default Variables ---
    local TARGET_DIR=""
    local -a FILE_TYPES=() # `-a` declares an array
    local -a SKIP_DIRS=()
    local OUTPUT_FILE="output.txt"
    local PARALLEL_JOBS
    PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)

    # --- Color Setup ---
    local C_RED="" C_GREEN="" C_YELLOW="" C_BOLD="" C_RESET=""
    # `[[ -t 2 ]]` checks if stderr (stream 2) is an interactive terminal.
    if [[ -t 2 ]]; then
        C_RED=$(tput setaf 1)
        C_GREEN=$(tput setaf 2)
        C_YELLOW=$(tput setaf 3)
        C_BOLD=$(tput bold)
        C_RESET=$(tput sgr0)
    fi

    # --- Argument Parsing ---
    # `while [[ $# -gt 0 ]]` loops as long as there are arguments.
    while [[ $# -gt 0 ]]; do
        # `case` is a clean way to handle different options.
        case "$1" in
            --output)
                # `${2:-}` checks if argument #2 exists and is not empty.
                [[ -z "${2:-}" ]] && { printf "%sError: --output requires a filename.%s\n" "$C_RED" "$C_RESET" >&2; exit 1; }
                OUTPUT_FILE="$2"
                shift 2 # Consume the flag and its value.
                ;;
            --skip)
                shift # Consume '--skip'.
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    SKIP_DIRS+=("$1")
                    shift
                done
                ;;
            --jobs|-j)
                [[ -z "${2:-}" ]] && { printf "%sError: --jobs requires a number.%s\n" "$C_RED" "$C_RESET" >&2; exit 1; }
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --help) print_help; exit 0 ;;
            --version) echo "file-crawler.sh version 5.1 (Parallel & Portable)"; exit 0 ;;
            -*) printf "%sError: Unknown option '%s'%s\n" "$C_RED" "$1" "$C_RESET" >&2; print_help; exit 1 ;;
            *)
                if [[ -z "$TARGET_DIR" ]]; then
                    TARGET_DIR="$1"
                else
                    FILE_TYPES+=("$1")
                fi
                shift # Consume one argument.
                ;;
        esac
    done

    # --- Input Validation ---
    if [[ -z "$TARGET_DIR" || ${#FILE_TYPES[@]} -eq 0 ]]; then
        printf "%sError: Missing target directory or file extensions.%s\n" "$C_RED" "$C_RESET" >&2
        print_help; exit 1
    fi
    if [[ ! -d "$TARGET_DIR" ]]; then
        printf "%sError: '%s' is not a valid directory.%s\n" "$C_RED" "$TARGET_DIR" "$C_RESET" >&2; exit 1
    fi

    # --- Path and File Setup ---
    BASE_CWD=$(get_realpath ".")
    CWD_BASE_NAME=$(basename "$BASE_CWD")
    TARGET_DIR=$(get_realpath "$TARGET_DIR")
    OUTPUT_FILE_ABS=$(get_realpath "$OUTPUT_FILE")

    local temp_dir
    temp_dir=$(mktemp -d "file-crawler.XXXXXX")
    
    local progress_pid=""
    # `trap` ensures that if the user presses Ctrl+C (INT) or the script is
    # killed (TERM), we always clean up the progress bar and temp directory.
    trap 'echo -e "\nAborted by user." >&2; [[ -n "$progress_pid" ]] && kill "$progress_pid" 2>/dev/null; rm -rf "$temp_dir"; exit 130' INT TERM

    # --- Build `find` command arguments ---
    # Building the command in an array is the safest way to handle arguments
    # with spaces or special characters.
    local -a find_args=("$TARGET_DIR")
    # `-path ... -prune -o` tells find: if you see this path, don't descend into it.
    find_args+=(-path "$OUTPUT_FILE_ABS" -prune -o)

    if [[ ${#SKIP_DIRS[@]} -gt 0 ]]; then
        find_args+=(-type d '(')
        for dir in "${SKIP_DIRS[@]}"; do find_args+=(-name "$dir" -o); done
        find_args[${#find_args[@]}-1]=')'
        find_args+=(-prune -o)
    fi

    find_args+=(-type f '(')
    for ext in "${FILE_TYPES[@]}"; do find_args+=(-name "*.$ext" -o); done
    find_args[${#find_args[@]}-1]=')'

    # --- STAGE 1: Count total files for the progress bar ---
    printf "%s%sCalculating total files...%s\n" "$C_BOLD" "$C_YELLOW" "$C_RESET" >&2
    local total_files
    total_files=$(find "${find_args[@]}" -print | wc -l)
    
    if [[ "$total_files" -eq 0 ]]; then
        printf "%sNo matching files found.%s\n" "$C_YELLOW" "$C_RESET" >&2
        rm -rf "$temp_dir"
        exit 0
    fi
    
    # --- STAGE 2: Process files in parallel with progress monitoring ---
    printf "%s%sProcessing %d files...%s\n" "$C_BOLD" "$C_YELLOW" "$total_files" "$C_RESET" >&2

    progress_bar_updater "$$" "$temp_dir" "$total_files" &
    progress_pid=$!

    # This is the main processing pipeline.
    # 1. `find ... -print0`: Prints filenames separated by a null character (`\0`).
    #    This is the only 100% safe way to handle filenames with spaces or newlines.
    # 2. `xargs -0`: Reads the null-separated list.
    #    -P: Runs jobs in parallel.
    #    -I {}: Replaces `{}` with the filename.
    #    `bash -c '...'`: For each file, it starts a new bash shell to run our function.
    #    The `_` is a placeholder for `$0` inside the new shell.
    find "${find_args[@]}" -print0 | xargs -0 -P "$PARALLEL_JOBS" -I {} \
        bash -c 'process_file_parallel "{}" "$1"' _ "$temp_dir"

    sleep 0.2 # Allow the progress bar to hit 100%.
    kill "$progress_pid" 2>/dev/null || true
    printf "\r" >&2 # Clear the progress bar line.

    # --- Finalization ---
    printf "\n%s%sConsolidating output...%s\n" "$C_BOLD" "$C_YELLOW" "$C_RESET" >&2
    # `cat` all the small temporary result files into the single, final output file.
    find "$temp_dir" -type f -name 'output.*' -exec cat {} + > "$OUTPUT_FILE"

    # --- Success Message and Cleanup ---
    printf "%s%sCrawling complete. Processed %d files.%s\n" "$C_BOLD" "$C_GREEN" "$total_files" "$C_RESET" >&2
    printf "%sOutput saved to: %s%s\n" "$C_GREEN" "$OUTPUT_FILE_ABS" "$C_RESET" >&2

    rm -rf "$temp_dir"
    trap - INT TERM # Disable the trap on a successful exit.
}

# This calls the `main` function and passes all command-line arguments (`$@`).
main "$@"