#!/bin/bash

###############################################################################
# USAGE:
#   ./file-crawler.sh <directory> <file_extension1> [file_extension2 ...] \
#                     [--skip <skip_dir1> <skip_dir2> ...]
#
# EXAMPLES:
#   1) ./file-crawler.sh ./src ts tsx
#      => Crawls all .ts and .tsx files inside ./src, skipping no dirs
#
#   2) ./file-crawler.sh . ts tsx --skip node_modules dist .git
#      => Crawls all .ts & .tsx files in current dir, skipping node_modules/,
#         dist/, and .git/ directories (and subtrees).
###############################################################################

# 1) Parse the first argument as target directory
TARGET_DIR="${1:-.}"
if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: '$TARGET_DIR' is not a valid directory."
  echo "Usage: $0 <directory> <ext1> [ext2 ...] [--skip skipDir1 skipDir2 ...]"
  exit 1
fi
shift

# 2) Prepare arrays to store file extensions & skip directories
FILE_TYPES=()
SKIP_DIRS=()

# 3) Parse the remaining arguments
PARSE_SKIP=false
while [[ $# -gt 0 ]]; do
  arg="$1"
  shift
  if [[ "$arg" == "--skip" ]]; then
    PARSE_SKIP=true
  else
    if [ "$PARSE_SKIP" = true ]; then
      # We are currently parsing skip directories
      SKIP_DIRS+=("$arg")
    else
      # Otherwise, these are file extensions
      FILE_TYPES+=("$arg")
    fi
  fi
done

# 4) Check we have at least one file extension
if [ ${#FILE_TYPES[@]} -eq 0 ]; then
  echo "Error: No file extensions provided."
  echo "Usage: $0 <directory> <ext1> [ext2 ...] [--skip skipDir1 skipDir2 ...]"
  exit 1
fi

# 5) Prepare the output file
OUTPUT_FILE="output.txt"
> "$OUTPUT_FILE"

###############################################################################
# 6) Build the 'find' command
#
#    General logic:
#    1) If we have directories to skip, we do:
#         find <TARGET_DIR>
#           -type d \( -name <skip1> -o -name <skip2> \) -prune -false -o
#    2) Then match files:
#           -type f \( -name "*.<ext1>" -o -name "*.<ext2>" \) -print
###############################################################################
FIND_CMD="find \"$TARGET_DIR\""

# 6a) If there are skip directories, add a clause that prunes those directories
if [ ${#SKIP_DIRS[@]} -gt 0 ]; then
  FIND_CMD+=" -type d \\( "
  for i in "${!SKIP_DIRS[@]}"; do
    if [ "$i" != "0" ]; then
      FIND_CMD+=" -o "
    fi
    FIND_CMD+=" -name \"${SKIP_DIRS[$i]}\""
  done
  FIND_CMD+=" \\) -prune -false -o"
fi

# 6b) Now add the part that finds matching files by extension
FIND_CMD+=" -type f \\("
for i in "${!FILE_TYPES[@]}"; do
  if [ "$i" != "0" ]; then
    FIND_CMD+=" -o"
  fi
  FIND_CMD+=" -name \"*.${FILE_TYPES[$i]}\""
done
FIND_CMD+=" \\) -print"

# 7) Count how many files match
TOTAL_FILES=$(eval "$FIND_CMD" 2>/dev/null | wc -l)
if [ "$TOTAL_FILES" -eq 0 ]; then
  echo "No matching files found in '$TARGET_DIR'"
  echo "  Extensions: ${FILE_TYPES[*]}"
  if [ ${#SKIP_DIRS[@]} -gt 0 ]; then
    echo "  Skipped dirs: ${SKIP_DIRS[*]}"
  fi
  exit 0
fi

# 8) Initialize counters for the progress bar
CURRENT_COUNT=0

# ---------------------------------------------------------------------------
# Function: draw_progress_bar
# ---------------------------------------------------------------------------
draw_progress_bar() {
  local progress=$(( CURRENT_COUNT * 100 / TOTAL_FILES ))
  local bar_length=40  # total length of the bar
  local filled=$(( progress * bar_length / 100 ))
  local empty=$(( bar_length - filled ))

  printf "\r["
  printf "%0.s#" $(seq 1 $filled)
  printf "%0.s-" $(seq 1 $empty)
  printf "] %d%% (%d/%d files)" "$progress" "$CURRENT_COUNT" "$TOTAL_FILES"
}

# ---------------------------------------------------------------------------
# Function: process_file
# ---------------------------------------------------------------------------
process_file() {
  local file="$1"
  CURRENT_COUNT=$((CURRENT_COUNT + 1))

  # Write filename (relative path) as a header
  echo "\n${file}" >> "$OUTPUT_FILE"

  # Append file content
  cat "$file" >> "$OUTPUT_FILE"

  # Update progress bar
  draw_progress_bar
}

# 9) Execute the find command and process each file
eval "$FIND_CMD" | while read -r file; do
  process_file "$file"
done

# 10) Print completion message
echo "\nCrawling completed. Output saved in $OUTPUT_FILE."