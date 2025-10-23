#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-$PROJECT_ROOT/docker-compose.yml}"
CHAIN_DATA_DIR="${CHAIN_DATA_DIR:-$PROJECT_ROOT/chain_data}"
SHARED_PROOF_DIR="${SHARED_PROOF_DIR:-$CHAIN_DATA_DIR/db/shared}"
DEFAULT_PROOF_STORAGE_URL="https://adiproofs.blob.core.windows.net/shared"

export DOCKER_COMPOSE_FILE CHAIN_DATA_DIR SHARED_PROOF_DIR

usage() {
  cat <<'EOF'
Usage: external-node.sh <command> [options]

Commands:
  download   Download shared proof storage from Azure Blob Storage.
  start      Start the external node and proxy via docker compose.
  stop       Stop the external node and proxy.
  down       Stop and remove the external node containers.
  status     Show docker compose services status.
  logs       Follow logs from the external node containers.
  pull       Pull the latest container images defined in docker-compose.yml.
  help       Show this help text.

Environment variables:
  PROOF_STORAGE_URL   Azure Blob URL or SAS URL for shared proofs (defaults to https://adiproofs.blob.core.windows.net/shared).
  DOCKER_COMPOSE_FILE Path to docker-compose.yml (defaults to repository file).
  CHAIN_DATA_DIR      Host directory that maps to /chain inside the container.
  SHARED_PROOF_DIR    Destination for shared proofs (defaults to $CHAIN_DATA_DIR/db/shared).
  GENERAL_L1_RPC_URL  (required) L1 RPC endpoint used by the external node.
EOF
}

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" >&2
}

fatal() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local binary="$1"
  shift || true
  if ! command -v "$binary" >/dev/null 2>&1; then
    fatal "${*:-Command '$binary' is required but was not found in PATH.}"
  fi
}

compose() {
  [[ -n "${CHAIN_DATA_DIR:-}" ]] || fatal "CHAIN_DATA_DIR must be set."
  export CHAIN_DATA_DIR

  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$DOCKER_COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "$DOCKER_COMPOSE_FILE" "$@"
  else
    fatal "docker compose plugin (Docker 20.10+) or docker-compose is required."
  fi
}

download_shared() {
  local destination="$SHARED_PROOF_DIR"
  local source="${PROOF_STORAGE_URL:-$DEFAULT_PROOF_STORAGE_URL}"
  local delete_destination="false"
  local verbose="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--destination)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        destination="$2"
        shift 2
        ;;
      -s|--source)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        source="$2"
        shift 2
        ;;
      -f|--force)
        delete_destination="true"
        shift
        ;;
      -v|--verbose)
        verbose="true"
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage: external-node.sh download [--source <azure-sas-url>] [--destination <dir>] [--force]

Options:
  --source, -s       Azure Blob SAS URL to copy from (defaults to PROOF_STORAGE_URL or the adi snapshot).
  --destination, -d  Directory to store shared proofs (defaults to SHARED_PROOF_DIR).
  --force, -f        Force destination to match source (enables deletion of local files missing in source).
  --verbose, -v      Emit azcopy progress logs.
EOF
        return 0
        ;;
      *)
        fatal "Unknown download option: $1"
        ;;
    esac
  done

  [[ -n "$source" ]] || fatal "No Azure source provided. Use --source or set PROOF_STORAGE_URL."

  require_command azcopy "azcopy is required for downloading from Azure Blob Storage."

  mkdir -p "$destination"
  if [[ -n "${CHAIN_DATA_DIR:-}" && "$destination" == "$CHAIN_DATA_DIR"* ]]; then
    local parent_dir
    parent_dir="$(dirname "$destination")"
    chmod 0777 "$destination" >/dev/null 2>&1 || true
    if [[ "$parent_dir" == "$CHAIN_DATA_DIR"* ]]; then
      chmod 0777 "$parent_dir" >/dev/null 2>&1 || true
    fi
  fi
  log "Syncing shared proofs from $source to $destination"

  local azcopy_args=("sync" "$source" "$destination" "--recursive" "--delete-destination=$delete_destination")
  if [[ "$verbose" == "true" ]]; then
    azcopy_args+=("--log-level=WARN")
  else
    azcopy_args+=("--log-level=INFO")
  fi

  azcopy "${azcopy_args[@]}"
  log "Sync completed."
}

ensure_container_dir() {
  local dir="$1"
  mkdir -p "$dir"
  if ! chmod 0777 "$dir"; then
    fatal "Failed to adjust permissions for $dir (required for container writes)."
  fi
}

start_node() {
  local l1_rpc_url="${GENERAL_L1_RPC_URL:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--l1-rpc-url)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        l1_rpc_url="$2"
        shift 2
        ;;
      -h|--help)
        cat <<'EOF'
Usage: external-node.sh start [--l1-rpc-url <url>]

Options:
  --l1-rpc-url, -u  Provide the required L1 RPC URL (alternatively set GENERAL_L1_RPC_URL).
EOF
        return 0
        ;;
      *)
        fatal "Unknown start option: $1"
        ;;
    esac
  done

  [[ -n "$l1_rpc_url" ]] || fatal "L1 RPC URL is required. Use --l1-rpc-url or set GENERAL_L1_RPC_URL."

  ensure_container_dir "$CHAIN_DATA_DIR"
  ensure_container_dir "$CHAIN_DATA_DIR/db"
  ensure_container_dir "$CHAIN_DATA_DIR/db/node1"
  ensure_container_dir "$CHAIN_DATA_DIR/db/block_dumps"
  ensure_container_dir "$SHARED_PROOF_DIR"

  GENERAL_L1_RPC_URL="$l1_rpc_url"
  export GENERAL_L1_RPC_URL
  log "Starting ADI external node container (L1 RPC URL configured)."
  compose up -d
  log "External node is starting. Check logs with './external-node.sh logs'."
}

stop_node() {
  log "Stopping ADI external node container (container preserved)."
  compose stop
}

down_node() {
  log "Stopping and removing ADI external node stack."
  compose down
}

show_status() {
  compose ps
}

follow_logs() {
  compose logs -f
}

pull_image() {
  log "Pulling container images."
  compose pull
}

main() {
  local command="${1:-help}"
  shift || true

  case "$command" in
    download) download_shared "$@" ;;
    start) start_node "$@" ;;
    stop) stop_node ;;
    down) down_node ;;
    status) show_status ;;
    logs) follow_logs ;;
    pull) pull_image ;;
    help|-h|--help) usage ;;
    *)
      fatal "Unknown command '$command'. Run './external-node.sh help' for usage."
      ;;
  esac
}

main "$@"
