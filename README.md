# ❄️ FrostGPU

> **Stateless GPU workstations on GCP. Pay only when you compute — $0.00 when idle.**

**FrostGPU** implements a *freeze-and-thaw* pattern for GPU-heavy workloads. Your environment and data are frozen into cheap cold storage between sessions. When you're ready to work, thaw a fresh Spot VM in seconds — fully loaded, ready to run.

Provision → Work → Persist → Destroy. All in one lifecycle.

---

### Architecture: Freeze the State, Rent the Compute

Most cloud GPUs bill you for the persistent disk as long as the VM exists, even when it's "Stopped." **FrostGPU** breaks the workstation into three cost-optimized layers:

1. **❄️ Immutable Environment (Snapshots)**: Your OS, drivers, and `uv/python` environments are baked into "Golden Images." Snapshots are compressed — a 50GB disk often results in a **10GB snapshot**.
2. **⚡ Ephemeral Compute (Spot GPU)**: High-performance GPUs at Spot rates (~$0.18/hr for T4). Destroyed immediately after your session.
3. **🗄️ Cold Progress (GCS Sync)**: Datasets and training outputs are synced to Regional GCS buckets ($0.02/GB) and mapped back to the VM disk on every boot.

---

### The Economics of Cold Persistence

For a standard workspace in `europe-west2` (London) with a **10GB OS Snapshot** and **90GB of GCS Data**:

| Persistence Mode | Status | Monthly Cost |
| :--- | :--- | :--- |
| **GCP Always On** | Running 24/7 | **~$129.60** |
| **RunPod/Lambda** | Stopped Pod | ~$20.00 |
| **Traditional GCP** | Stopped VM (Disk only) | ~$10.00 |
| **❄️ FrostGPU** | **Snapshot + GCS (frozen)** | **~$2.30** |

---

### Session Lifecycle

1. **`make up`** — Thaw your workstation
   - Finds the latest timestamped Golden Image
   - Provisions a fresh Spot VM with your configured hardware
   - Rsyncs your models/datasets from GCS to the local disk
2. **`make tunnel`** — Start working
   - Opens an SSH session with multi-port forwarding (Jupyter, WebUIs, Tensorboard) based on `SSH_FORWARDS`
3. **`make sync`** — Save mid-session
   - Pushes current progress to GCS
4. **`make down`** — Freeze and destroy
   - Final rsync to GCS and **destruction of the VM**

---

### 📋 Prerequisites

Before you begin, ensure you have:
1. **GCP Account**: A project with billing enabled.
2. **gcloud CLI**: [Installed](https://cloud.google.com/sdk/docs/install) and authenticated (`gcloud auth login`).
3. **Project Quota**: GPU quota in your target zone (e.g., `NVIDIA_T4_GPUS`, `NVIDIA_L4_GPUS`).
4. **APIs Enabled**: Compute Engine and Cloud Storage APIs must be active.

---

### Getting Started

**1. Configure**
Copy the base environment file and fill in your values.
```bash
cp .env.example .env
vi .env
```

**2. Initialize & Bake your Golden Image**
One-time setup — creates your infrastructure and bakes the first frozen environment.
```bash
make init     # Creates GCS bucket + base VM
make ssh      # Install your tools/libraries (ComfyUI, PyTorch, etc.)
make snapshot # Bakes the Golden Image and destroys the VM
```

**3. Daily Workflow**
```bash
make up       # Thaw — spin up your workstation
make tunnel   # Work — open port tunnels (7860, 8888, etc.)
make down     # Freeze — sync to GCS and destroy the VM
```

**4. Model Downloader (Cost Optimization)**
Download large models without paying GPU rates. The downloader VM uses
**GCS FUSE mounting** (`gcsfuse`) — directories defined in `SYNC_DIRS` are
mounted directly onto GCS. Anything written to the local path lands in GCS in real-time, no manual sync required.
```bash
make dl-up    # Launch a cheap e2-small VM with FUSE-mounted GCS dirs
make dl-ssh   # SSH in and download models (writes go straight to GCS)
make dl-down  # Unmount and destroy the instance
```
> **Note:** `make dl-sync` is a no-op for downloader VMs — it exits early
> with a warning since files are already in GCS via the FUSE mount.

---

### 🌐 Multi-Environment Management

Maintain multiple environments (e.g., L4 in Seoul vs. T4 in London) with multiple `.env` files.

**1. Create a new environment**
```bash
cp .env .env.t4
vi .env.t4  # Update ZONE, MACHINE_TYPE, ACCELERATOR, and VM_NAME
```

**2. Switch environments**
Change the `ENV` variable at the top of the `Makefile`:
```makefile
ENV ?= .env.t4  # Point to your new environment
```
All commands (`make up`, `make down`, etc.) will automatically target that environment.

---

### ⚙️ Advanced: Power User Workflows

#### 🔄 Re-baking the Golden Image
If you install new system libraries (`apt`) or global Python packages:
1. `make up`
2. `make ssh` → install new tools
3. `make snapshot`

A new timestamped image is created and used for all future boots.

#### 🔌 Arbitrary Port Tunneling
Define ports in your `.env` to open them during `make tunnel`:
```bash
SSH_FORWARDS=8888:8888 6006:6006 7860:7860
```

#### 📂 Directory Syncing
Map VM directories to GCS subdirectories in your `.env`:
```bash
SYNC_DIRS=/home/user/models:models /home/user/outputs:outputs
```

---

### 🛠️ Troubleshooting & Logs
- **Slow init**: SSH in and run `tail -f /var/log/gpu-driver-install.log`.
- **Spot preemption**: Your work is safe in GCS up to the last `make sync`. Just run `make up` to thaw a fresh VM.
- **Full cleanup**: Delete all cloud resources with `make teardown`.
