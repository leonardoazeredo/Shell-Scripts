#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# file-crawler.sh - Concatenate source files with formatted headers
#
# USAGE:
#   file-crawler.sh [--output OUTPUT_FILE] <directory> <file_extension1> \
#                   [file_extension2 ...] [--skip <skip_dir1> <skip_dir2> ...]
#
# EXAMPLES:
#   1) file-crawler.sh ./src ts tsx
#      => Crawls all .ts and .tsx files inside ./src
#
#   2) file-crawler.sh . ts tsx --skip node_modules dist .git \
#         --output combined.txt
#      => Crawls current dir, skips specified dirs, saves to combined.txt
#
# OUTPUT FORMAT:
#   ```file_extension
#   // relative/path/to/file
#   file_content
#   
#   ```
###############################################################################

# Check if script is in PATH and offer to add it
check_script_in_path() {
    local script_name script_path script_dir
    script_name=$(basename "$0")
    
    # Check if script is found in PATH
    if ! command -v "$script_name" >/dev/null 2>&1; then
        script_path=$(cd "$(dirname "$0")" && pwd -P)/$script_name
        echo "Note: $script_name is not in your PATH"
        echo "You can run it from anywhere by adding it to your PATH"
        read -p "Would you like to add it to PATH for this session? [y/N] " response
        
        if [[ "$response" =~ ^[Yy] ]]; then
            # Add to PATH only if not already present
            if [[ ":$PATH:" != *":$(dirname "$script_path"):"* ]]; then
                export PATH="$(dirname "$script_path"):$PATH"
                echo "Added to PATH. You can now run '$script_name' from anywhere"
            else
                echo "Directory already in PATH"
            fi
        fi
        echo ""
    fi
}

# Run PATH check
check_script_in_path

# Initialize variables
TARGET_DIR=""
FILE_TYPES=()
SKIP_DIRS=()
OUTPUT_FILE="output.txt"
OUTPUT_FILE_ABS=""
PARSE_SKIP=false
PARSE_OUTPUT=false

# Handle interrupt signal
trap 'echo -e "\n\nAborted by user!"; exit 1' INT

# Print help function
print_help() {
    awk '/^# USAGE:/{flag=1; next} /^# ?#/{flag=0} flag' "$0" | \
    sed -e 's/^# \?//' -e 's/^#//'
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
        --skip)
            PARSE_SKIP=true
            shift
            ;;
        --output)
            if [ $# -lt 2 ]; then
                echo "Error: --output requires a filename" >&2
                exit 1
            fi
            PARSE_OUTPUT=true
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help)
            print_help
            exit 0
            ;;
        --version)
            echo "file-crawler.sh version 1.1"
            exit 0
            ;;
        *)
            if [ "$PARSE_OUTPUT" = true ]; then
                OUTPUT_FILE="$arg"
                PARSE_OUTPUT=false
                shift
            elif [ "$PARSE_SKIP" = true ]; then
                SKIP_DIRS+=("$arg")
                shift
            elif [ -z "$TARGET_DIR" ]; then
                TARGET_DIR="$arg"
                shift
            else
                FILE_TYPES+=("$arg")
                shift
            fi
            ;;
    esac
done

# Validate target directory
if [ -z "$TARGET_DIR" ]; then
    echo "Error: No target directory specified" >&2
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: '$TARGET_DIR' is not a valid directory" >&2
    exit 1
fi

# Validate at least one file extension
if [ ${#FILE_TYPES[@]} -eq 0 ]; then
    echo "Error: No file extensions provided" >&2
    echo "Usage: $0 [--output FILE] <directory> <ext1> [ext2 ...] [--skip skipDir1 ...]" >&2
    exit 1
fi

# Create output directory if needed and verify write access
output_dir=$(dirname "$OUTPUT_FILE")
if [ ! -d "$output_dir" ]; then
    mkdir -p "$output_dir" || {
        echo "Error: Failed to create output directory '$output_dir'" >&2
        exit 1
    }
fi

if ! touch "$OUTPUT_FILE" 2>/dev/null; then
    echo "Error: '$OUTPUT_FILE' is not writable" >&2
    exit 1
fi

# Get absolute paths for current directory and output file
BASE_CWD=$(cd . && pwd -P)
CWD_BASE_NAME=$(basename "$BASE_CWD")
TARGET_DIR=$(cd "$TARGET_DIR" && pwd -P)
OUTPUT_FILE_ABS=$(cd "$(dirname "$OUTPUT_FILE")" && pwd -P)/$(basename "$OUTPUT_FILE")

# Initialize output file
> "$OUTPUT_FILE"

###############################################################################
# Build find command safely using arrays
###############################################################################
find_args=("$TARGET_DIR")

# Add skip directories if any
if [ ${#SKIP_DIRS[@]} -gt 0 ]; then
    find_args+=(-type d)
    find_args+=('(')
    for dir in "${SKIP_DIRS[@]}"; do
        find_args+=(-name "$dir" -o)
    done
    # Remove last -o and close parentheses
    unset 'find_args[${#find_args[@]}-1]'
    find_args+=(')')
    find_args+=(-prune -false -o)
fi

# Add file type matching
find_args+=(-type f '(')
for ext in "${FILE_TYPES[@]}"; do
    find_args+=(-name "*.$ext" -o)
done
unset 'find_args[${#find_args[@]}-1]'  # Remove last -o
find_args+=(')')
find_args+=(-print)  # Standard output (not null-delimited)

# Count total files safely
FILES_TMP=$(mktemp)
find "${find_args[@]}" 2>/dev/null > "$FILES_TMP"
TOTAL_FILES=$(wc -l < "$FILES_TMP" | tr -d '[:space:]')

if [ "$TOTAL_FILES" -eq 0 ]; then
    echo "No matching files found in '$TARGET_DIR'"
    echo "  Extensions: ${FILE_TYPES[*]}"
    [ ${#SKIP_DIRS[@]} -gt 0 ] && echo "  Skipped dirs: ${SKIP_DIRS[*]}"
    rm -f "$FILES_TMP"
    exit 0
fi

###############################################################################
# Processing functions
###############################################################################
CURRENT_COUNT=0
BAR_LENGTH=40
UPDATE_FREQ=10  # Update progress bar every N files

# Improved progress bar with padding
draw_progress_bar() {
    local progress=$((CURRENT_COUNT * 100 / TOTAL_FILES))
    local filled=$((progress * BAR_LENGTH / 100))
    local bar
    
    # Build bar string
    printf -v bar '%*s' "$filled"
    bar=${bar// /#}
    
    # Pad with dashes
    printf -v bar '%-*s' "$BAR_LENGTH" "$bar"
    bar=${bar// /-}
    
    printf "\r[%s] %d%% (%d/%d files)" "$bar" "$progress" "$CURRENT_COUNT" "$TOTAL_FILES"
}

# Determine relative display path
get_display_path() {
    local file_abs="$1"
    local display_path
    
    if [[ "$file_abs" == "$BASE_CWD"/* ]]; then
        display_path="$CWD_BASE_NAME/${file_abs#$BASE_CWD/}"
    else
        display_path="$file_abs"
    fi
    
    echo "$display_path"
}

process_file() {
    local file="$1"
    
    # Skip output file itself
    if [[ "$file" -ef "$OUTPUT_FILE_ABS" ]]; then
        return 0
    fi
    
    # Verify file readability
    if [ ! -r "$file" ]; then
        echo "Warning: Skipping unreadable file '$file'" >&2
        return 1
    fi
    
    # Get file extension
    local filename display_path extension
    filename=$(basename -- "$file")
    extension="${filename##*.}"
    if [[ "$extension" == "$filename" ]]; then
        extension="text"
    fi
    
    # Get display path
    display_path=$(get_display_path "$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")")
    
    # Write file header and content
    printf '```%s\n' "$extension" >> "$OUTPUT_FILE"
    printf '// %s\n' "$display_path" >> "$OUTPUT_FILE"
    
    # Append file content with error handling
    if ! cat -- "$file" >> "$OUTPUT_FILE" 2>/dev/null; then
        echo "Error: Failed to read '$file'" >&2
        return 1
    fi
    
    # Add closing code block
    printf '\n```\n\n' >> "$OUTPUT_FILE"
    
    return 0
}

###############################################################################
# Main processing loop
###############################################################################
echo "Starting crawl of $TOTAL_FILES files"
echo "Output: $OUTPUT_FILE"
[ ${#SKIP_DIRS[@]} -gt 0 ] && echo "Skipping: ${SKIP_DIRS[*]}"
echo ""

# Process files using temporary file
while IFS= read -r file; do
    if process_file "$file"; then
        # Count successful processing
        ((CURRENT_COUNT++))
    else
        # Count skipped files too
        ((CURRENT_COUNT++))
    fi
    
    # Always update progress bar at the end
    if (( CURRENT_COUNT == TOTAL_FILES )); then
        draw_progress_bar
    # Otherwise update periodically
    elif (( CURRENT_COUNT % UPDATE_FREQ == 0 )); then
        draw_progress_bar
    fi
done < "$FILES_TMP"

# Always draw 100% at the end
if (( CURRENT_COUNT < TOTAL_FILES )); then
    CURRENT_COUNT=$TOTAL_FILES
    draw_progress_bar
fi

# Clean up temporary file
rm -f "$FILES_TMP"

# Final status
printf "\n\nCrawling completed. Processed %d/%d files.\n" "$CURRENT_COUNT" "$TOTAL_FILES"
echo "Output saved to: $OUTPUT_FILE"
exit 0