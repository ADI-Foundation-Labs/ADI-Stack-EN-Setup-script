#!/usr/bin/env sh
set -e

# Proof storage sync script
# Runs periodically to keep local proof storage in sync with Azure Blob Storage

SYNC_INTERVAL="${SYNC_INTERVAL:-60}"  # Default: 1 minute
SOURCE="${PROOF_STORAGE_URL:-https://adimainnet.blob.core.windows.net/proofs}"
DESTINATION="${SHARED_PROOF_DIR:-/chain/db/shared}"
DELETE_DESTINATION="${DELETE_DESTINATION:-false}"

log() {
  printf '[%s] [proof-sync] %s\n' "$(date -Iseconds)" "$*"
}

if [ -z "$SOURCE" ]; then
  log "ERROR: PROOF_STORAGE_URL is not set"
  exit 1
fi

log "Starting proof storage sync service"
log "Source: $SOURCE"
log "Destination: $DESTINATION"
log "Sync interval: ${SYNC_INTERVAL}s"
log "Delete destination: $DELETE_DESTINATION"

# Create destination directory if it doesn't exist
mkdir -p "$DESTINATION"

# Main sync loop
while true; do
  log "Starting proof sync..."

  if azcopy sync "$SOURCE" "$DESTINATION" \
    --recursive \
    --delete-destination="$DELETE_DESTINATION" \
    --log-level=INFO; then
    log "Proof sync completed successfully"
  else
    exit_code=$?
    log "ERROR: Proof sync failed with exit code $exit_code"
    # Continue running even if sync fails
  fi

  log "Next sync in ${SYNC_INTERVAL}s"
  sleep "$SYNC_INTERVAL"
done
