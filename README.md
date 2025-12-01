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
   ```

3. Start the external node (or pass the URL directly):

   ```bash
   # Mainnet
   ./external-node.sh start
   ./external-node.sh start --l1-rpc-url https://{RPC}

   # Testnet
   ./external-node.sh --testnet start --l1-rpc-url https://{RPC}
   ```

   The start command prepares the data directory (and its key subdirectories).
   Starting the stack also launches:
   - The `cloudflared-tcp-proxy` service, which exposes the Cloudflare Access-protected replay endpoint on port `3053` inside the Docker network
   - The `proof-sync` service, which automatically syncs new proofs from Azure Blob Storage every 1 minute (configurable via `PROOF_SYNC_INTERVAL`)

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
