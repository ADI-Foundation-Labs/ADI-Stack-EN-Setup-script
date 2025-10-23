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
   ./external-node.sh start --l1-rpc-url https://your-l1-endpoint
   ```

   The start command prepares `CHAIN_DATA_DIR` (and its key subdirectories) with permissive permissions so the container can initialise RocksDB on the first run.

Additional helpful commands:

- `./external-node.sh status` — show the compose service status.
- `./external-node.sh logs` — follow container logs.
- `./external-node.sh stop` — stop the container.
- `./external-node.sh down` — stop and remove the container.
- `./external-node.sh pull` — pull the latest container image.

Set `CHAIN_DATA_DIR`, `SHARED_PROOF_DIR`, or `DOCKER_COMPOSE_FILE` to override defaults if your layout differs from this repository.  
The `start` command requires `GENERAL_L1_RPC_URL`; prefix the command with `GENERAL_L1_RPC_URL=...` if you prefer not to export it permanently.
