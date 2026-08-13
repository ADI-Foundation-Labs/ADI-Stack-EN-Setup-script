# ADI External Node

Helper scripts and configuration for running an ADI external node on **mainnet**, **testnet**, or **devnet**.

## Prerequisites

- Docker Engine with the `docker compose` plugin (or the legacy `docker-compose` binary).

## Network Selection

By default, the script runs on **mainnet**. To run on testnet or devnet, use the `--testnet` or `--devnet` flag:

```bash
# Mainnet (default)
./external-node.sh start --l1-rpc-url https://your-l1-endpoint

# Testnet
./external-node.sh --testnet start --l1-rpc-url https://your-l1-endpoint

# Devnet
./external-node.sh --devnet start --l1-rpc-url https://your-l1-endpoint
```

### Network Configuration

| Network | Main RPC                                             | Data Directory   |
|---------|------------------------------------------------------|------------------|
| Mainnet | `https://rpc.adifoundation.ai`                       | `./mainnet_data` |
| Testnet | `https://rpc.ab.testnet.adifoundation.ai`            | `./testnet_data` |
| Devnet  | `https://rpc-devnet6.dev.internal.adifoundation.ai/` | `./devnet_data`  |

## Usage

`--l1-rpc-url` (or `GENERAL_L1_RPC_URL`) is the only value you need to provide. `--boot-node-urls` and `--external-network-secret-key` are optional:

- **`--boot-node-urls`** falls back to a hardcoded default for the selected network if omitted.
- **`--external-network-secret-key`** is auto-generated on first start if omitted; the script prints the generated value — save it and reuse it on subsequent starts to keep your P2P node identity stable.

```bash
# Mainnet
./external-node.sh start --l1-rpc-url https://your-l1-endpoint

# Testnet
./external-node.sh --testnet start --l1-rpc-url https://your-l1-endpoint

# Devnet
./external-node.sh --devnet start --l1-rpc-url https://your-l1-endpoint
```

Or via environment variable:

```bash
export GENERAL_L1_RPC_URL="https://your-l1-endpoint"
./external-node.sh start
```

To override the defaults (e.g. to reuse a previously generated secret key, or to point at your own boot nodes), pass the optional flags explicitly:

```bash
./external-node.sh start \
  --l1-rpc-url https://your-l1-endpoint \
  --boot-node-urls "enode://<pubkey>@<ip>:3060" \
  --external-network-secret-key <your-key>
```

The start command creates the data directory and its key subdirectories automatically.

## Additional Commands

All commands support the `--testnet` and `--devnet` flags:

```bash
./external-node.sh [--testnet|--devnet] <command>
```

- `status` — show the compose service status.
- `logs` — follow container logs.
- `stop` — stop the containers.
- `down` — stop and remove the containers.
- `pull` — pull the latest container image.

Set `CHAIN_DATA_DIR` or `DOCKER_COMPOSE_FILE` to override defaults if your layout differs from this repository.

## Network Identity Setup

Every external node requires a secret key for P2P identity and a list of boot nodes for peer discovery. Both are optional when starting the node — see below.

### 1. Generate the secret key

If you don't provide `EXTERNAL_NETWORK_SECRET_KEY` (or `--external-network-secret-key`), `start` auto-generates one with `openssl rand -hex 32` and prints it. To pin your node's P2P identity across restarts, generate one yourself and reuse it:

```bash
openssl rand -hex 32
```

Keep this value private — it uniquely identifies your node in the P2P network.

```bash
export EXTERNAL_NETWORK_SECRET_KEY=<64-hex-chars>
```

### 2. Derive the public key (optional)

Needed only if you want to share your node as a boot node for others:

```bash
cast wallet public-key --private-key <private-key>
# Output: 0x92c5f671...
```

The output can be used as-is in the enode URL — no need to strip the `0x` prefix.

### 3. Configure boot nodes

Boot nodes are used for initial peer discovery. If you don't provide `BOOT_NODE_URLS` (or `--boot-node-urls`), `start` falls back to a hardcoded default for the selected network. You only need to set this to point at your own boot nodes. Format:

```
enode://<public-key>@<ip-or-host>:<port>
```

- `public-key` — 128 hex chars, no `0x` prefix
- `ip-or-host` — publicly reachable address of the boot node
- `port` — default `3060`

```bash
# Single boot node
export BOOT_NODE_URLS="enode://abcd1234...@1.2.3.4:3060"

# Multiple boot nodes (comma-separated)
export BOOT_NODE_URLS="enode://key1@host1:3060,enode://key2@host2:3060"
```

## Exposed Ports

Mainnet, testnet, and devnet all use the same ports. Don't run more than one network on the same host at once, or use `CONTAINER_PREFIX` and remap ports via `docker-compose.override.yml` if you need to.

| Port           | Service            | Notes                                |
|----------------|--------------------|--------------------------------------|
| `3050`         | JSON-RPC           | `rpc_address`                        |
| `3060` TCP+UDP | P2P devp2p         | peer discovery and block propagation |
| `3071`         | Health / status    | `status_server_address`              |
| `3312`         | Prometheus metrics | `observability_prometheus_port`      |

Ensure port `3060` is open for both TCP and UDP inbound traffic.

## Upgrades

For version-specific upgrade instructions, see the [upgrades](./upgrades/) directory:

- [v0.8.4 → v0.10.0](./upgrades/v0.8.4_to_v0.10.0.md) — **Breaking upgrade** requiring full chain resync
- [v0.13.0 → v0.20.12](upgrades/v0.13.0_to_v0.20.12.md) — P2P replaces HTTP replay, proof-sync removed