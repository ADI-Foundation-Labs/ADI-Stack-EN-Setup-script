# ADI External Node

Helper scripts and configuration for running an ADI external node on **mainnet** or **testnet**.

## Prerequisites

- Docker Engine with the `docker compose` plugin (or the legacy `docker-compose` binary).

## Network Selection

By default, the script runs on **mainnet**. To run on testnet, use the `--testnet` flag:

```bash
# Mainnet (default)
./external-node.sh start --l1-rpc-url https://your-l1-endpoint

# Testnet
./external-node.sh --testnet start --l1-rpc-url https://your-l1-endpoint
```

### Network Configuration

| Network | Main RPC | Data Directory |
|---------|----------|----------------|
| Mainnet | `https://rpc.adifoundation.ai` | `./mainnet_data` |
| Testnet | `https://rpc.ab.testnet.adifoundation.ai` | `./testnet_data` |

## Usage

1. Generate a network secret key (unique per node):

   ```bash
   openssl rand -hex 32
   ```

2. Set the required environment variables:

   ```bash
   export GENERAL_L1_RPC_URL="https://your-l1-endpoint"
   export EXTERNAL_NETWORK_SECRET_KEY="<64-hex-chars from step 1>"
   export BOOT_NODE_URLS="enode://<pubkey>@<ip>:3060"
   ```

3. Start the external node:

   ```bash
   # Mainnet
   ./external-node.sh start

   # Testnet
   ./external-node.sh --testnet start
   ```

   Or pass all values as CLI flags:

   ```bash
   ./external-node.sh start \
     --l1-rpc-url https://your-l1-endpoint \
     --boot-node-urls "enode://<pubkey>@<ip>:3060" \
     --external-network-secret-key <your-key>

   ./external-node.sh --testnet start \
     --l1-rpc-url https://your-l1-endpoint \
     --boot-node-urls "enode://<pubkey>@<ip>:3060" \
     --external-network-secret-key <your-key>
   ```

   The start command creates the data directory and its key subdirectories automatically.

## Additional Commands

All commands support the `--testnet` flag for testnet operation:

```bash
./external-node.sh [--testnet] <command>
```

- `status` — show the compose service status.
- `logs` — follow container logs.
- `stop` — stop the containers.
- `down` — stop and remove the containers.
- `pull` — pull the latest container image.

Set `CHAIN_DATA_DIR` or `DOCKER_COMPOSE_FILE` to override defaults if your layout differs from this repository.

## Network Identity Setup

Every external node requires a secret key for P2P identity and a list of boot nodes for peer discovery.

### 1. Generate the secret key

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
# Output: 0x04abcd...
```

> Remove the `0x04` prefix before using the key in an enode URL.

### 3. Configure boot nodes

Boot nodes are used for initial peer discovery. Format:

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
- [v0.10.0 → v0.19.0](./upgrades/v0.10.0_to_v0.19.0.md) — P2P replaces HTTP replay, proof-sync removed