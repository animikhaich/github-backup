#!/bin/bash
set -e

# Ensure required variables are set
if [ -z "$GH_USER" ] || [ -z "$S3_BUCKET" ]; then
  echo "Error: GH_USER and S3_BUCKET must be set."
  exit 1
fi

BACKUP_DIR="./backup_stage/github.com/$GH_USER"
SOURCE_DIR="./source_stage"

# Verify backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
  echo "Error: Backup directory $BACKUP_DIR does not exist."
  ls -R backup_stage || echo "backup_stage not found"
  exit 1
fi

echo "Starting parallel S3 upload and source extraction..."

# 1. Start syncing the bare git repositories to s3://bucket/git/
# We run this in the background
echo "Starting upload of bare git repositories to s3://$S3_BUCKET/git/..."
aws s3 sync "$BACKUP_DIR" "s3://$S3_BUCKET/git/" --no-progress --delete &
PID_GIT_SYNC=$!

# 2. Extract source code in parallel
echo "Extracting source code from bare repositories..."
mkdir -p "$SOURCE_DIR"

# Check if there are any git repositories to process
if [ -n "$(find "$BACKUP_DIR" -maxdepth 1 -name "*.git" -print -quit)" ]; then
  # Use find and xargs to process repositories in parallel
  # -P $(nproc) uses as many processes as available CPU cores
  # We use bash -c with arguments to avoid quoting issues.
  # $0 is the script name (unused), $1 is repo_path, $2 is source_dir
  export SOURCE_DIR
  find "$BACKUP_DIR" -maxdepth 1 -name "*.git" -print0 | xargs -0 -P $(nproc) -I {} bash -c '
    repo_path="$1"
    source_dir="$2"
    repo_name=$(basename "$repo_path" .git)
    target_path="$source_dir/$repo_name"

    # Clone the repository (depth 1 for speed, single branch) from the local bare repo
    # using file:// protocol.
    # We use GIT_LFS_SKIP_SMUDGE=1 to prevent downloading large files (LFS)
    if ! out=$(GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 "file://$(realpath "$repo_path")" "$target_path" 2>&1); then
      echo "Failed to extract $repo_name. Error:" >&2
      echo "$out" >&2
      # Log the error but continue so other repos are still processed
    fi
  ' _ "{}" "$SOURCE_DIR" || true
else
  echo "No repositories found in $BACKUP_DIR"
fi

echo "Source extraction complete."

# 3. Start syncing the extracted source code to s3://bucket/source/
echo "Starting upload of source code to s3://$S3_BUCKET/source/..."
aws s3 sync "$SOURCE_DIR" "s3://$S3_BUCKET/source/" --no-progress --delete &
PID_SOURCE_SYNC=$!

# 4. Wait for both sync processes to complete
echo "Waiting for uploads to finish..."
FAIL=0

wait $PID_GIT_SYNC || FAIL=1
wait $PID_SOURCE_SYNC || FAIL=1

if [ $FAIL -eq 0 ]; then
  echo "All uploads completed successfully."
else
  echo "One or more uploads failed."
  # The user requested that the GitHub Actions job should not fail due to these errors.
  # We log the failure but exit with success.
  exit 0
fi
