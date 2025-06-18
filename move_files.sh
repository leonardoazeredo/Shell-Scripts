#!/bin/bash

# Check for arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <source_directory> [destination_directory]"
    exit 1
fi

# Set source and destination directories
SOURCE_DIR="$1"
DEST_DIR="${2:-"$(dirname "$SOURCE_DIR")/organised_files"}"
LOG_FILE="./file_move.log"

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

# Initialize log file
> "$LOG_FILE"  # Truncate log file if it already exists

# Count total files for progress bar
TOTAL_FILES=$(find "$SOURCE_DIR" -type f | wc -l)
if [[ $TOTAL_FILES -eq 0 ]]; then
    echo "No files found in $SOURCE_DIR to move. Exiting."
    exit 0
fi

# Function to print a progress bar
show_progress() {
    local PROGRESS=$1
    local TOTAL=$2
    local WIDTH=50  # Progress bar width in characters

    local FILLED=$((PROGRESS * WIDTH / TOTAL))
    local EMPTY=$((WIDTH - FILLED))

    printf "\r["
    printf "#%.0s" $(seq 1 $FILLED)
    printf " %.0s" $(seq 1 $EMPTY)
    printf "] %d%% (%d/%d)" $((PROGRESS * 100 / TOTAL)) $PROGRESS $TOTAL
}

# Move files with duplication check and logging
FILE_COUNT=0
find "$SOURCE_DIR" -type f | while IFS= read -r FILE; do
    BASENAME=$(basename "$FILE")
    DEST_PATH="$DEST_DIR/$BASENAME"

    # Check for duplication
    if [[ -e "$DEST_PATH" ]]; then
        # Append "_dupe" to the file name if a duplicate exists
        DEST_PATH="$DEST_DIR/${BASENAME%.*}_dupe.${BASENAME##*.}"
    fi

    # Move the file and log the action
    if mv "$FILE" "$DEST_PATH"; then
        echo "Moved: $FILE -> $DEST_PATH" >> "$LOG_FILE"
    else
        echo "Failed: $FILE" >> "$LOG_FILE"
    fi

    # Update progress
    FILE_COUNT=$((FILE_COUNT + 1))
    show_progress $FILE_COUNT $TOTAL_FILES

done

# Print a new line after progress bar completion
echo

echo "File moving complete. See $LOG_FILE for details."