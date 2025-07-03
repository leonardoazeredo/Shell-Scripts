#!/usr/bin/env bash
#
# file-crawler.sh - Concatenate source files with formatted headers.
# This script has been refactored to apply modern Bash best practices.
# Version 2.1: Corrected a bug where a local variable was out of scope for an EXIT trap.

set -euo pipefail

#
# Prints the usage instructions extracted from the script's header comments.
#
print_help() {
    awk '/^# USAGE:/{flag=1; next} /^# ?#/{flag=0} flag' "$0" | \
    sed -e 's/^# \?//' -e 's/^#//'
}

#
# Draws a progress bar to stderr.
# Globals: CURRENT_COUNT, TOTAL_FILES, BAR_LENGTH
#
draw_progress_bar() {
    # Ensure TOTAL_FILES is not zero to prevent division by zero error
    [[ ${TOTAL_FILES:-0} -eq 0 ]] && return

    local progress=$((CURRENT_COUNT * 100 / TOTAL_FILES))
    local filled=$((progress * BAR_LENGTH / 100))
    local bar

    # Build bar string
    printf -v bar '%*s' "$filled" ''
    bar=${bar// /#}

    # Pad with dashes
    printf -v bar '%-*s' "$BAR_LENGTH" "$bar"
    bar=${bar// /-}

    # Print to stderr to not interfere with stdout
    printf "\r[%s] %d%% (%d/%d files)" "$bar" "$progress" "$CURRENT_COUNT" "$TOTAL_FILES" >&2
}

#
# Determines the relative display path for a given absolute file path.
# Globals: BASE_CWD, CWD_BASE_NAME
#
get_display_path() {
    local file_abs="$1"
    local display_path

    # Prepend the parent directory name if the file is within the original CWD
    if [[ "$file_abs" == "$BASE_CWD"/* ]]; then
        display_path="${CWD_BASE_NAME}/${file_abs#$BASE_CWD/}"
    else
        display_path="$file_abs"
    fi

    echo "$display_path"
}

#
# Processes a single file: adds its header and content to the output file.
# Globals: OUTPUT_FILE, OUTPUT_FILE_ABS
#
process_file() {
    local file="$1"

    # Resolve the absolute path of the file being processed
    local file_abs
    file_abs="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"

    # Skip the output file itself to prevent infinite loops
    if [[ "$file_abs" -ef "$OUTPUT_FILE_ABS" ]]; then
        return 0
    fi

    # Verify file readability before processing
    if [[ ! -r "$file" ]]; then
        printf "\nWarning: Skipping unreadable file '%s'\n" "$file" >&2
        return 1
    fi

    local filename extension display_path
    filename=$(basename -- "$file")
    extension="${filename##*.}"
    # Use 'text' as a fallback extension
    [[ "$extension" == "$filename" ]] && extension="text"

    display_path=$(get_display_path "$file_abs")

    # Write file header and content to the output file
    {
        printf '```%s\n' "$extension"
        printf '// %s\n' "$display_path"
        # Use cat without suppressing its errors. If it fails, pipefail will catch it.
        cat -- "$file"
        printf '\n```\n\n'
    } >> "$OUTPUT_FILE"
}

#
# Main function to encapsulate all script logic.
#
main() {
    # --- Configuration and Default Variables ---
    local TARGET_DIR=""
    local -a FILE_TYPES=()
    local -a SKIP_DIRS=()
    local OUTPUT_FILE="output.txt"
    local -a find_args=()

    # Progress bar settings
    local CURRENT_COUNT=0
    local TOTAL_FILES=0
    local BAR_LENGTH=40

    # --- Argument Parsing ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --output option requires a filename." >&2
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --skip)
                shift # Consume '--skip'
                # Consume all subsequent arguments until the next option (starting with --)
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    SKIP_DIRS+=("$1")
                    shift
                done
                ;;
            --help)
                print_help
                exit 0
                ;;
            --version)
                echo "file-crawler.sh version 2.1 (Refactored)"
                exit 0
                ;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                print_help
                exit 1
                ;;
            *)
                # Positional arguments
                if [[ -z "$TARGET_DIR" ]]; then
                    TARGET_DIR="$1"
                else
                    FILE_TYPES+=("$1")
                fi
                shift
                ;;
        esac
    done

    # --- Input Validation ---
    if [[ -z "$TARGET_DIR" ]]; then
        echo "Error: No target directory specified." >&2
        print_help
        exit 1
    fi
    if [[ ! -d "$TARGET_DIR" ]]; then
        echo "Error: '$TARGET_DIR' is not a valid directory." >&2
        exit 1
    fi
    if [[ ${#FILE_TYPES[@]} -eq 0 ]]; then
        echo "Error: No file extensions provided." >&2
        print_help
        exit 1
    fi

    # --- Path and File Setup ---
    local output_dir
    output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir" || {
        echo "Error: Failed to create output directory '$output_dir'." >&2
        exit 1
    }
    # Check writability by trying to create/touch the file
    if ! touch "$OUTPUT_FILE" 2>/dev/null; then
        echo "Error: Output file '$OUTPUT_FILE' is not writable." >&2
        exit 1
    fi

    # Get absolute paths for consistent path logic
    local BASE_CWD CWD_BASE_NAME OUTPUT_FILE_ABS
    BASE_CWD="$(cd . && pwd -P)"
    CWD_BASE_NAME="$(basename "$BASE_CWD")"
    TARGET_DIR="$(cd "$TARGET_DIR" && pwd -P)"
    OUTPUT_FILE_ABS="$(cd "$(dirname "$OUTPUT_FILE")" && pwd -P)/$(basename "$OUTPUT_FILE")"

    # Initialize/clear the output file
    >"$OUTPUT_FILE"

    # --- Build `find` command arguments safely ---
    find_args+=("$TARGET_DIR")

    if [[ ${#SKIP_DIRS[@]} -gt 0 ]]; then
        find_args+=(-type d '(')
        for dir in "${SKIP_DIRS[@]}"; do
            find_args+=(-name "$dir" -o)
        done
        # Replace the trailing '-o' with ')'
        find_args[${#find_args[@]}-1]=')'
        find_args+=(-prune -o)
    fi

    find_args+=(-type f '(')
    for ext in "${FILE_TYPES[@]}"; do
        find_args+=(-name "*.$ext" -o)
    done
    find_args[${#find_args[@]}-1]=')'
    find_args+=(-print)

    # --- File Discovery and Processing ---
    local temp_file
    temp_file=$(mktemp)

    # *** FIX: Trap for interrupt signals to clean up the temp file. ***
    # This trap handles Ctrl+C (INT) or a kill command (TERM).
    trap 'echo -e "\n\nAborted by user." >&2; rm -f "$temp_file"; exit 130' INT TERM

    # Run find, allowing it to report errors (e.g., permission denied)
    find "${find_args[@]}" > "$temp_file"

    # Read the line count directly
    TOTAL_FILES=$(< "$temp_file" wc -l)

    if [[ "$TOTAL_FILES" -eq 0 ]]; then
        echo "No matching files found in '$TARGET_DIR'" >&2
        echo "  Extensions: ${FILE_TYPES[*]}" >&2
        [[ ${#SKIP_DIRS[@]} -gt 0 ]] && echo "  Skipped dirs: ${SKIP_DIRS[*]}" >&2
        # *** FIX: Manually clean up temp file on this exit path. ***
        rm -f "$temp_file"
        trap - INT TERM # Clear the trap
        exit 0
    fi

    echo "Starting crawl of $TOTAL_FILES files..." >&2
    echo "Output will be saved to: $OUTPUT_FILE" >&2
    [[ ${#SKIP_DIRS[@]} -gt 0 ]] && echo "Skipping directories: ${SKIP_DIRS[*]}" >&2
    echo "" >&2

    # --- Main Processing Loop ---
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            if process_file "$file"; then
                ((CURRENT_COUNT++))
            else
                # Also increment count for failed files to keep progress accurate
                ((CURRENT_COUNT++))
            fi
            draw_progress_bar
        fi
    done < "$temp_file"

    # --- Finalization ---
    # *** FIX: Explicitly clean up the temporary file on normal completion. ***
    # This is the crucial fix. We remove the file before the function exits
    # and the 'temp_file' variable goes out of scope.
    rm -f "$temp_file"

    # Disable the trap now that we're done with the resource it was protecting.
    trap - INT TERM

    echo "" >&2
    echo "Crawling complete. Processed $CURRENT_COUNT/$TOTAL_FILES files." >&2
    echo "Output saved to: $OUTPUT_FILE_ABS" >&2
}

# Call main with all script arguments
main "$@"