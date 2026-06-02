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

# Network-specific configurations
declare -A MAINNET_CONFIG=(
    [name]="mainnet"
    [data_dir]="mainnet_data"
)

declare -A TESTNET_CONFIG=(
    [name]="testnet"
    [data_dir]="testnet_data"
)

# Function to load network configuration
load_network_config() {
    local -n config
    case "$NETWORK" in
        mainnet) config=MAINNET_CONFIG ;;
        testnet) config=TESTNET_CONFIG ;;
        *) fatal "Unknown network: $NETWORK. Supported: mainnet, testnet" ;;
    esac

    NETWORK_NAME="${config[name]}"
    DEFAULT_DATA_DIR="${config[data_dir]}"

    # Set chain data directory (can be overridden by env var)
    CHAIN_DATA_DIR="${CHAIN_DATA_DIR:-$PROJECT_ROOT/$DEFAULT_DATA_DIR}"

    # Set docker-compose file based on network (can be overridden by env var)
    if [[ -z "$DOCKER_COMPOSE_FILE" ]]; then
        DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.${NETWORK}.yml"
    fi

    # Export for docker-compose (only what's needed, rest is in compose files)
    export CHAIN_DATA_DIR
    export DOCKER_COMPOSE_FILE
}

usage() {
  cat <<'EOF'
Usage: external-node.sh [--testnet] <command> [options]

Network Selection:
  --testnet            Use testnet configuration (default: mainnet)
  --network <name>     Select network explicitly (mainnet or testnet)

Commands:
  start      Start the external node via docker compose.
  stop       Stop the external node and all services.
  down       Stop and remove all containers.
  status     Show docker compose services status.
  logs       Follow logs from all containers.
  pull       Pull the latest container images for the selected network.
  help       Show this help text.

Environment variables:
NETWORK                     Network to use: mainnet (default) or testnet.
                            Determines which configuration, endpoints and docker-compose file are used.
EN_VERSION                  External node image version tag (network-specific default).
                            Overrides the Docker image version of the external node.
DOCKER_COMPOSE_FILE         Path to docker-compose file (defaults to docker-compose.<network>.yml).
                            Allows overriding the default compose file per network.
CHAIN_DATA_DIR              Host directory that maps to /chain inside the container.
                            Stores blockchain data and state on the host machine.
GENERAL_L1_RPC_URL          (required) L1 RPC endpoint used by the external node.
                            Must be a full Ethereum-compatible RPC (e.g. Infura, Alchemy, or self-hosted).
EXTERNAL_NETWORK_SECRET_KEY Private key used to identify and authenticate the external node in the P2P network.
                            Auto-generated if not set. Reuse the same key on restarts to keep your P2P node identity.
BOOT_NODE_URLS              (required) Comma-separated list of bootnode enode URLs used for P2P peer discovery.
Server versions:
  Mainnet: v0.20.12-b1 (docker-compose.mainnet.yml)
  Testnet: v0.20.12-b1 (docker-compose.testnet.yml)

Examples:
  # Run on mainnet (default)
  ./external-node.sh start --l1-rpc-url https://eth-mainnet.example.com

  # Run on testnet
  ./external-node.sh --testnet start --l1-rpc-url https://eth-sepolia.example.com
EOF
}

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" >&2
}

fatal() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
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
        boot_node_urls="$2"
        shift 2
        ;;
      --external-network-secret-key)
        [[ $# -ge 2 ]] || fatal "Missing value for $1."
        external_network_secret_key="$2"
        shift 2
        ;;
      -h|--help)
        cat <<'EOF'
Usage: external-node.sh start [--l1-rpc-url <url>]

Options:
  --l1-rpc-url, -u               Provide the required L1 RPC URL (alternatively set GENERAL_L1_RPC_URL).
  --boot-node-url                Provide the required boot node URL (alternatively set BOOT_NODE_URLS).
  --external-network-secret-key  Provide the external network secret key (alternatively set EXTERNAL_NETWORK_SECRET_KEY).
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
  [[ -n "$boot_node_urls" ]] || fatal "BOOT NODE URL is required. Use --boot-node-url or set BOOT_NODE_URLS."
  if [[ -z "$external_network_secret_key" ]]; then
    external_network_secret_key="$(openssl rand -hex 32)"
    log "EXTERNAL_NETWORK_SECRET_KEY not provided — generated automatically: $external_network_secret_key"
    log "Save this key and reuse it on restarts to keep your P2P node identity stable."
  fi

  ensure_container_dir "$CHAIN_DATA_DIR"
  ensure_container_dir "$CHAIN_DATA_DIR/db"
  ensure_container_dir "$CHAIN_DATA_DIR/db/node1"

  GENERAL_L1_RPC_URL="$l1_rpc_url"
  BOOT_NODE_URLS="$boot_node_urls"
  EXTERNAL_NETWORK_SECRET_KEY="$external_network_secret_key"
  export GENERAL_L1_RPC_URL
  export BOOT_NODE_URLS
  export EXTERNAL_NETWORK_SECRET_KEY
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
