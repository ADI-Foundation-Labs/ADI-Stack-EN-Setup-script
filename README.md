# ADI Testnet External Node

Helper scripts and configuration for running an ADI Testnet external node.

## Prerequisites

- Docker Engine with the `docker compose` plugin (or the legacy `docker-compose` binary).
- [`azcopy`](https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-v10) installed locally for downloading the shared proofs snapshot.

## Usage

1. Sync the shared proof storage (defaults to `./chain_data/db/shared`):

   ```bash
   ./external-node.sh download
   ```

   Pass `--destination` to sync into another directory, `--force` to delete local files that no longer exist in the Azure snapshot, or `--verbose` to stream detailed azcopy logs.

2. Provide the L1 RPC URL (required):

   ```bash
   export GENERAL_L1_RPC_URL="https://your-l1-endpoint"
   ```

3. Start the external node (or pass the URL directly):

   ```bash
   ./external-node.sh start
   ./external-node.sh start --l1-rpc-url https://{RPC}
   ```

   The start command prepares `CHAIN_DATA_DIR` (and its key subdirectories).
   Starting the stack also launches:
   - The `cloudflared-tcp-proxy` service, which exposes the Cloudflare Access-protected replay endpoint on port `3053` inside the Docker network
   - The `proof-sync` service, which automatically syncs new proofs from Azure Blob Storage every 1 minute (configurable via `PROOF_SYNC_INTERVAL`)

Additional helpful commands:

- `./external-node.sh status` — show the compose service status.
- `./external-node.sh logs` — follow container logs.
- `./external-node.sh stop` — stop the container.
- `./external-node.sh down` — stop and remove the container.
- `./external-node.sh pull` — pull the latest container image.

Set `CHAIN_DATA_DIR`, `SHARED_PROOF_DIR`, or `DOCKER_COMPOSE_FILE` to override defaults if your layout differs from this repository.
The `start` command requires `GENERAL_L1_RPC_URL`; prefix the command with `GENERAL_L1_RPC_URL=...` if you prefer not to export it permanently.

## Automatic Proof Synchronization

The `proof-sync` sidecar container automatically keeps your local proof storage synchronized with Azure Blob Storage. This prevents the external node from crashing when new proofs are processed but not yet available locally.

### Configuration

Customize the proof sync behavior using these environment variables:

- `PROOF_SYNC_INTERVAL` — Sync interval in seconds (default: `60` = 1 minutes)
- `PROOF_STORAGE_URL` — Azure Blob URL or SAS URL for shared proofs (default: `https://adiproofs.blob.core.windows.net/shared`)
- `PROOF_SYNC_DELETE` — Set to `true` to delete local files that no longer exist in Azure (default: `false`)

Example:

```bash
export PROOF_SYNC_INTERVAL=180  # Sync every 3 minutes
export PROOF_SYNC_DELETE=true   # Keep local storage in exact sync
./external-node.sh start
```

The proof-sync service runs continuously alongside the external node and logs each sync operation. Check its logs with:

```bash
docker logs -f adi_testnet_proof_sync
```

## Exposed ports

- `3050` — `external_node` JSON-RPC endpoint (`rpc_address`).
- `3054` — External Node Block Replay port so it can be shared further (`sequencer_block_replay_server_address`)
- `3071` — Node status/health server (`status_server_address`).
- `3312` — Prometheus metrics endpoint (`general_prometheus_port`).

## Upgrades

For version-specific upgrade instructions, see the [upgrades](./upgrades/) directory:

- [v0.8.4 to v0.10.0](./upgrades/v0.8.4_to_v0.10.0.md) - **Breaking upgrade** requiring full chain resync

## Common issues

### Committed batch is not present in proof storage

The `proof-sync` sidecar service automatically prevents this issue by continuously syncing new proofs from Azure Blob Storage.

If you still encounter this error:
1. Check that the `proof-sync` container is running: `docker ps | grep proof_sync`
2. Check proof-sync logs: `docker logs adi_testnet_proof_sync`
3. Manually sync if needed: `./external-node.sh download`
4. Consider reducing `PROOF_SYNC_INTERVAL` for more frequent syncs
