#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Network configuration
NETWORK="${NETWORK:-mainnet}"

# Docker compose file is set after network is determined
# Can be overridden via DOCKER_COMPOSE_FILE env var
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-}"

# Default boot node URLs for networks running P2P (devnet, testnet).
# mainnet is still on v0.13.0 (pre-P2P) — it'll get its own upgrade later.
DEVNET_DEFAULT_BOOT_NODES="enode://0x92c5f671dd80c87890c05a1aea5175d3473469acad922e926b6aba9246ee3e801a892d9d8e76d2d272c9d3b2c081f23c379434d0a40a3b27549d2cf9f706fbfb@20.216.31.107:3060"

TESTNET_DEFAULT_BOOT_NODES="enode://0x89317fb81e979bd5b0d102f2c3da3ccb569cf2b2802fb0c3af562b625b1d695dc44b5c6ef3848697dce61e6cc9a8f9fe6ad89ff08cfb2ab4e51bc7a55986ee6f@20.233.0.124:3060"

# Network-specific configurations
declare -A MAINNET_CONFIG=(
    [name]="mainnet"
    [data_dir]="mainnet_data"
    [proof_storage_url]="https://adimainnet.blob.core.windows.net/proofs"
    [proof_sync_enabled]="true"
    [p2p_enabled]="false"
)

declare -A TESTNET_CONFIG=(
    [name]="testnet"
    [data_dir]="testnet_data"
    [p2p_enabled]="true"
    [boot_nodes]="$TESTNET_DEFAULT_BOOT_NODES"
)

declare -A DEVNET_CONFIG=(
    [name]="devnet"
    [data_dir]="devnet_data"
    [p2p_enabled]="true"
    [boot_nodes]="$DEVNET_DEFAULT_BOOT_NODES"
)

# Function to load network configuration
load_network_config() {
    local -n config
    case "$NETWORK" in
        mainnet) config=MAINNET_CONFIG ;;
        testnet) config=TESTNET_CONFIG ;;
        devnet) config=DEVNET_CONFIG ;;
        *) fatal "Unknown network: $NETWORK. Supported: mainnet, testnet, devnet" ;;
    esac

    NETWORK_NAME="${config[name]}"
    DEFAULT_DATA_DIR="${config[data_dir]}"
    DEFAULT_PROOF_STORAGE_URL="${config[proof_storage_url]:-}"
    PROOF_SYNC_ENABLED="${config[proof_sync_enabled]:-false}"
    P2P_ENABLED="${config[p2p_enabled]}"
    DEFAULT_BOOT_NODE_URLS="${config[boot_nodes]:-}"

    # Set chain data directory (can be overridden by env var)
    CHAIN_DATA_DIR="${CHAIN_DATA_DIR:-$PROJECT_ROOT/$DEFAULT_DATA_DIR}"
    SHARED_PROOF_DIR="${SHARED_PROOF_DIR:-$CHAIN_DATA_DIR/db/shared}"

    # Set docker-compose file based on network (can be overridden by env var)
    if [[ -z "$DOCKER_COMPOSE_FILE" ]]; then
        DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.${NETWORK}.yml"
    fi

    # Export for docker-compose (only what's needed, rest is in compose files)
    export CHAIN_DATA_DIR SHARED_PROOF_DIR
    export PROOF_STORAGE_URL="${PROOF_STORAGE_URL:-$DEFAULT_PROOF_STORAGE_URL}"
    export CHAIN_DATA_DIR
    export DOCKER_COMPOSE_FILE
}

usage() {
  cat <<'EOF'
Usage: external-node.sh [--testnet|--devnet] <command> [options]

Network Selection:
  --testnet            Use testnet configuration (default: mainnet)
  --devnet             Use devnet configuration (default: mainnet)
  --network <name>     Select network explicitly (mainnet, testnet, or devnet)

Commands:
  download   Mainnet only. Initial/manual sync of shared proof storage from Azure Blob Storage.
             Note: When running, the proof-sync service automatically syncs new proofs.
             Not available on devnet or testnet — they don't use proof-sync (P2P networking instead).
  start      Start the external node via docker compose.
  stop       Stop the external node and all services.
  down       Stop and remove all containers.
  status     Show docker compose services status.
  logs       Follow logs from all containers.
  pull       Pull the latest container images for the selected network.
  help       Show this help text.

Environment variables:
NETWORK                     Network to use: mainnet (default), testnet, or devnet.
                            Determines which configuration, endpoints and docker-compose file are used.
EN_VERSION                  External node image version tag (network-specific default).
                            Overrides the Docker image version of the external node.
PROOF_STORAGE_URL           Azure Blob URL for shared proofs (network-specific default).
PROOF_SYNC_INTERVAL         Automatic sync interval in seconds (defaults to 60 = 1 minute).
PROOF_SYNC_DELETE           Set to 'true' to delete local files not in Azure (defaults to false)
DOCKER_COMPOSE_FILE         Path to docker-compose file (defaults to docker-compose.<network>.yml).
                            Allows overriding the default compose file per network.
CHAIN_DATA_DIR              Host directory that maps to /chain inside the container.
                            Stores blockchain data and state on the host machine.
GENERAL_L1_RPC_URL          (required) L1 RPC endpoint used by the external node.
                            Must be a full Ethereum-compatible RPC (e.g. Infura, Alchemy, or self-hosted).
EXTERNAL_NETWORK_SECRET_KEY Devnet/testnet only. Private key used to identify and authenticate the external node in the P2P network.
                            Auto-generated if not set. Reuse the same key on restarts to keep your P2P node identity.
BOOT_NODE_URLS              Devnet/testnet only. Comma-separated list of bootnode enode URLs used for P2P peer discovery.
                            Falls back to a hardcoded default for the network if not set.

Note: mainnet is still on v0.13.0 (pre-P2P) and doesn't use EXTERNAL_NETWORK_SECRET_KEY or
BOOT_NODE_URLS. Devnet and testnet run v0.20.12 with P2P networking. Mainnet will be upgraded
separately later — watch this repo for updates.

Server versions:
  Mainnet: v0.13.0-b4 (docker-compose.mainnet.yml)
  Testnet: v0.20.12-b1 (docker-compose.testnet.yml, P2P networking)
  Devnet:  v0.20.12-b1 (docker-compose.devnet.yml, P2P networking)

Examples:
  # Run on mainnet (default)
  ./external-node.sh start --l1-rpc-url https://eth-mainnet.example.com

  # Run on testnet
  ./external-node.sh --testnet start --l1-rpc-url https://eth-sepolia.example.com

  # Run on devnet
  ./external-node.sh --devnet start --l1-rpc-url https://eth-sepolia.example.com
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

  # Avoid "variable is not set" warnings from docker compose for commands
  # (stop, down, status, logs, pull) that don't go through start_node.
  export GENERAL_L1_RPC_URL="${GENERAL_L1_RPC_URL:-}"
  export EXTERNAL_NETWORK_SECRET_KEY="${EXTERNAL_NETWORK_SECRET_KEY:-}"
  export BOOT_NODE_URLS="${BOOT_NODE_URLS:-}"

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
  local source="$PROOF_STORAGE_URL"
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

Initial/manual sync of shared proof storage from Azure Blob Storage.

Note: When the node is running, the proof-sync sidecar service automatically
      syncs new proofs every PROOF_SYNC_INTERVAL seconds. This command is primarily
      for initial setup or manual synchronization.

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

  [[ "$PROOF_SYNC_ENABLED" == "true" ]] || fatal "download is not supported on $NETWORK_NAME — it doesn't use proof-sync/shared proof storage."

  [[ -n "$source" ]] || fatal "No Azure source provided. Use --source or set PROOF_STORAGE_URL."

  require_command azcopy "azcopy is required for downloading from Azure Blob Storage."

  log "Downloading proofs for $NETWORK_NAME network..."
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
  local boot_node_urls="${BOOT_NODE_URLS:-}"
  local external_network_secret_key="${EXTERNAL_NETWORK_SECRET_KEY:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--l1-rpc-url)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        l1_rpc_url="$2"
        shift 2
        ;;
      --boot-node-urls)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        [[ "$P2P_ENABLED" == "true" ]] || fatal "--boot-node-urls is only supported on networks with P2P networking (devnet, testnet). $NETWORK_NAME is still on v0.13.0."
        boot_node_urls="$2"
        shift 2
        ;;
      --external-network-secret-key)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        [[ "$P2P_ENABLED" == "true" ]] || fatal "--external-network-secret-key is only supported on networks with P2P networking (devnet, testnet). $NETWORK_NAME is still on v0.13.0."
        external_network_secret_key="$2"
        shift 2
        ;;
      -h|--help)
        cat <<'EOF'
Usage: external-node.sh start [--l1-rpc-url <url>]

Options:
  --l1-rpc-url, -u               Provide the required L1 RPC URL (alternatively set GENERAL_L1_RPC_URL).
  --boot-node-urls               Devnet/testnet only. Override the boot node URLs (alternatively set BOOT_NODE_URLS).
                                 Falls back to the hardcoded default for the network if omitted.
  --external-network-secret-key  Devnet/testnet only. Provide the external network secret key (alternatively set EXTERNAL_NETWORK_SECRET_KEY).
                                 Auto-generated if omitted; save the printed value for reuse.
EOF
        return 0
        ;;
      *)
        fatal "Unknown start option: $1"
        ;;
    esac
  done

  [[ -n "$l1_rpc_url" ]] || fatal "L1 RPC URL is required. Use --l1-rpc-url or set GENERAL_L1_RPC_URL."

  if [[ "$P2P_ENABLED" == "true" ]]; then
    if [[ -z "$boot_node_urls" ]]; then
      boot_node_urls="$DEFAULT_BOOT_NODE_URLS"
      log "BOOT_NODE_URLS not provided — using default for $NETWORK_NAME: $boot_node_urls"
    fi
    if [[ -z "$external_network_secret_key" ]]; then
      external_network_secret_key="$(openssl rand -hex 32)"
      log "EXTERNAL_NETWORK_SECRET_KEY not provided — generated automatically: $external_network_secret_key"
      log "Save this key and reuse it on restarts to keep your P2P node identity stable."
    fi
  fi

  ensure_container_dir "$CHAIN_DATA_DIR"
  ensure_container_dir "$CHAIN_DATA_DIR/db"
  ensure_container_dir "$CHAIN_DATA_DIR/db/node1"

  GENERAL_L1_RPC_URL="$l1_rpc_url"
  export GENERAL_L1_RPC_URL
  if [[ "$P2P_ENABLED" == "true" ]]; then
    BOOT_NODE_URLS="$boot_node_urls"
    EXTERNAL_NETWORK_SECRET_KEY="$external_network_secret_key"
    export BOOT_NODE_URLS
    export EXTERNAL_NETWORK_SECRET_KEY
  fi
  log "Starting ADI external node on $NETWORK_NAME (L1 RPC URL configured)."
  log "Data directory: $CHAIN_DATA_DIR"
  compose up -d
  log "External node is starting. Check logs with './external-node.sh logs'."
}

stop_node() {
  log "Stopping ADI $NETWORK_NAME external node (container preserved)."
  compose stop
}

down_node() {
  log "Stopping and removing ADI $NETWORK_NAME external node stack."
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
  # Parse global network flags first
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --testnet)
        NETWORK="testnet"
        shift
        ;;
      --devnet)
        NETWORK="devnet"
        shift
        ;;
      --network)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        NETWORK="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  # Load network configuration
  load_network_config

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
