# ADI External Node

Helper scripts and configuration for running an ADI external node on **mainnet** or **testnet**.

## Prerequisites

- Docker Engine with the `docker compose` plugin (or the legacy `docker-compose` binary).
- [`azcopy`](https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10) installed locally for downloading the shared proofs snapshot.

## Network Selection

By default, the script runs on **mainnet**. To run on testnet, use the `--testnet` flag:

```bash
# Mainnet (default)
./external-node.sh start --l1-rpc-url https://your-l1-endpoint

# Testnet
./external-node.sh --testnet start --l1-rpc-url https://your-l1-endpoint
```

### Network Configuration

| Network | Main RPC | Proof Storage | Data Directory |
|---------|----------|---------------|----------------|
| Mainnet | `https://rpc.adifoundation.ai` | `https://adimainnet.blob.core.windows.net/proofs` | `./mainnet_data` |
| Testnet | `https://rpc.ab.testnet.adifoundation.ai` | `https://adiproofs.blob.core.windows.net/shared` | `./testnet_data` |

## Usage

1. Sync the shared proof storage:

   ```bash
   # Mainnet
   ./external-node.sh download

   # Testnet
   ./external-node.sh --testnet download
   ```

   Pass `--destination` to sync into another directory, `--force` to delete local files that no longer exist in the Azure snapshot, or `--verbose` to stream detailed azcopy logs.

2. Provide the L1 RPC URL (required):

   ```bash
   export GENERAL_L1_RPC_URL="https://your-l1-endpoint"
   export BOOT_NODE_URLS="enode://..."
   export EXTERNAL_NETWORK_SECRET_KEY="your-private-key"
   ```

3. Start the external node (or pass the URL directly):

   ```bash
   # Mainnet
   ./external-node.sh start
   ./external-node.sh start --l1-rpc-url https://{RPC} \
     --boot-node-urls enode://... \
     --external-network-secret-key your-private-key

   # Testnet
   ./external-node.sh --testnet start --l1-rpc-url https://{RPC} \
     --boot-node-urls enode://... \
     --external-network-secret-key your-private-key
   ```

   The start command prepares the data directory (and its key subdirectories).
   Starting the stack also launches the `proof-sync` service, which automatically syncs new proofs from Azure Blob Storage every 1 minute (configurable via `PROOF_SYNC_INTERVAL`).

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

Set `CHAIN_DATA_DIR`, `SHARED_PROOF_DIR`, or `DOCKER_COMPOSE_FILE` to override defaults if your layout differs from this repository.
The `start` command requires `GENERAL_L1_RPC_URL`; prefix the command with `GENERAL_L1_RPC_URL=...` if you prefer not to export it permanently.

## Network Identity Setup

To run an external node, you need to generate a private key, derive its public key, and configure boot nodes.

1. Generate EXTERNAL_NETWORK_SECRET_KEY
   Generate a secure random private key:

   ```bash
   openssl rand -hex 32
   ```

   Example output:

   ```bash
   4f3c2a... (64 hex characters)
   ```

   Set it:

   ```bash
   export EXTERNAL_NETWORK_SECRET_KEY=<your-private-key>
   ```

2. Derive the public key:

   To get the public key:

   ```bash
   cast wallet public-key --private-key <private-key>
   ```
   Example output:
   ```bash
   0x04abcd...
   ```
   ⚠️ Remove the 0x prefix before using it in BOOT_NODE_URLS.
3. Configure boot nodes:

   Boot nodes are used for peer discovery. Format:
   ```bash
   enode://{public-key}@{ip-address-or-host}:{port}
   ```
   - public-key — without 0x
   - ip-address-or-host — public node address
   - port — default: 3060

   Example:
   ```bash
   export BOOT_NODE_URLS="enode://abcd1234...@1.2.3.4:3060"
   ```
   You can provide multiple boot nodes (comma-separated):
   ```bash
   export BOOT_NODE_URLS="enode://key1@host1:3060,enode://key2@host2:3060"
   ```

   Notes:
   - Keep your EXTERNAL_NETWORK_SECRET_KEY private — it identifies your node in the network.
   - The public key is derived from the private key and is safe to share.
   - Ensure your node is reachable on the specified port (default 3060) if acting as a boot node.

## Automatic Proof Synchronization

The `proof-sync` sidecar container automatically keeps your local proof storage synchronized with Azure Blob Storage. This prevents the external node from crashing when new proofs are processed but not yet available locally.

### Configuration

Customize the proof sync behavior using these environment variables:

- `PROOF_SYNC_INTERVAL` — Sync interval in seconds (default: `60` = 1 minute)
- `PROOF_STORAGE_URL` — Azure Blob URL or SAS URL for shared proofs (network-specific default)
- `PROOF_SYNC_DELETE` — Set to `true` to delete local files that no longer exist in Azure (default: `false`)

Example:

```bash
export PROOF_SYNC_INTERVAL=180  # Sync every 3 minutes
export PROOF_SYNC_DELETE=true   # Keep local storage in exact sync
./external-node.sh start
```

The proof-sync service runs continuously alongside the external node and logs each sync operation. Check its logs with:

```bash
# Mainnet
docker logs -f adi_mainnet_proof_sync

# Testnet
docker logs -f adi_testnet_proof_sync
```

## Exposed Ports

- `3050` — `external_node` JSON-RPC endpoint (`rpc_address`).
- `3054` — External Node Block Replay port so it can be shared further (`sequencer_block_replay_server_address`)
- `3071` — Node status/health server (`status_server_address`).
- `3312` — Prometheus metrics endpoint (`general_prometheus_port`).

## Upgrades

For version-specific upgrade instructions, see the [upgrades](./upgrades/) directory:

- [v0.8.4 to v0.10.0](./upgrades/v0.8.4_to_v0.10.0.md) - **Breaking upgrade** requiring full chain resync

## Common Issues

### Committed batch is not present in proof storage

The `proof-sync` sidecar service automatically prevents this issue by continuously syncing new proofs from Azure Blob Storage.

If you still encounter this error:
1. Check that the `proof-sync` container is running: `docker ps | grep proof_sync`
2. Check proof-sync logs: `docker logs <container_network_prefix>_proof_sync`
3. Manually sync if needed: `./external-node.sh download`
4. Consider reducing `PROOF_SYNC_INTERVAL` for more frequent syncs
