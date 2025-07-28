#!/bin/sh
#
# ==============================================================================
# Prompt Builder Script
# ==============================================================================
#
# Description:
#   This script generates a markdown file by populating a template. It finds
#   placeholder tags (e.g., <MY_CONTENT></MY_CONTENT>) within the template and
#   injects the content of a corresponding source file (e.g., MY_CONTENT.md)
#   *between* the opening and closing tags.
#
#   This version uses a robust string reconstruction method in awk to prevent
#   corruption of source content, correctly handling all special characters.
#
# Usage:
#   ./prompt_builder.sh -t <template_file> -s <source_directory> -o <output_file>
#
# ==============================================================================

# --- Configuration & Argument Parsing ---

set -e # Exit immediately if a command exits with a non-zero status.

OUTPUT_FILE=""
SOURCE_PATH="."
TEMPLATE_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -s|--source)
            SOURCE_PATH="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Usage: $0 -t <template> -s <source_dir> -o <output_file>" >&2
            exit 1
            ;;
    esac
done

# --- Input Validation ---

if [ -z "$TEMPLATE_FILE" ]; then
    echo "Error: No template specified. Use -t or --template to provide a template file." >&2
    exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found at '$TEMPLATE_FILE'" >&2
    exit 1
fi

# --- Output File and Directory Setup ---

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="output.md"
fi

OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"
cp "$TEMPLATE_FILE" "$OUTPUT_FILE"

# --- Helper Functions ---

normalize() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr -s '[:space:]-' '_' | tr -cd '[:alnum:]_'
}

# --- Tag Discovery and Mapping ---

TAG_MAP_FILE=$(mktemp)
trap 'rm -f "$TAG_MAP_FILE"' EXIT

echo "Discovering tags in template..."

grep -o '<[^/>][^>]*>' "$OUTPUT_FILE" |
  sed 's/^<//; s/>$//' |
  while IFS= read -r ORIGINAL_TAG; do
    NORMALIZED_TAG=$(normalize "$ORIGINAL_TAG")
    printf "%s\t%s\n" "$ORIGINAL_TAG" "$NORMALIZED_TAG"
  done |
  sort -u > "$TAG_MAP_FILE"

# --- Content Injection ---

echo "Processing tags and injecting content..."

while IFS=$'\t' read -r ORIGINAL_TAG NORMALIZED_TAG; do
    echo "  - Processing tag: <$ORIGINAL_TAG>"

    SOURCE_FILE_FOUND=""
    SOURCE_FILE_FOUND=$(find "$SOURCE_PATH" -maxdepth 1 -type f | while IFS= read -r FILE; do
        FILENAME=$(basename "$FILE")
        FILENAME_NOEXT=$(echo "$FILENAME" | sed 's/\.[^.]*$//')
        NORMALIZED_FILENAME=$(normalize "$FILENAME_NOEXT")

        if [ "$NORMALIZED_FILENAME" = "$NORMALIZED_TAG" ]; then
            echo "$FILE"
            break
        fi
    done)

    if [ -n "$SOURCE_FILE_FOUND" ]; then
        echo "    > Found matching source file: $SOURCE_FILE_FOUND"

        AWK_TEMP_FILE=$(mktemp)

        awk -v o_tag="$ORIGINAL_TAG" -v source_file="$SOURCE_FILE_FOUND" '
            BEGIN {
                # Read the entire source file into the `content` variable
                while ((getline line < source_file) > 0) {
                    content = content line "\n"
                }
                close(source_file)
                # Remove the final trailing newline to prevent extra blank lines
                sub(/\n$/, "", content)
            }
            {
                placeholder = "<" o_tag "></" o_tag ">"
                # As long as the placeholder exists on the current line...
                while ( (i = index($0, placeholder)) > 0 ) {
                    # Print the part of the line *before* the placeholder
                    printf "%s", substr($0, 1, i-1)

                    # Print the full, correctly formatted replacement block
                    printf "<%s>\n%s\n</%s>", o_tag, content, o_tag

                    # Update the line to be only the part *after* the placeholder
                    $0 = substr($0, i + length(placeholder))
                }
                # Print any remaining part of the line (or the whole line if no placeholder was found)
                print
            }
        ' "$OUTPUT_FILE" > "$AWK_TEMP_FILE" && mv "$AWK_TEMP_FILE" "$OUTPUT_FILE"

    else
        echo "    ! Warning: No matching source file found for tag <$ORIGINAL_TAG> (normalized: $NORMALIZED_TAG)"
    fi
done < "$TAG_MAP_FILE"

echo
echo "Content injection complete. Output written to: $OUTPUT_FILE"