# spot-diffusion

GPU workstations on GCP that cost **$0.00** when you aren't using them. 

This project implements a "Stateless Compute" pattern for GPU-heavy workloads. By splitting the OS, environment, and data into independent layers, it allows you to Provision → Work → Persist → Destroy in a single lifecycle.

### Architecture: The State vs. Compute Split

Most cloud GPUs bill you for the persistent disk (state) as long as the VM exists, even if it's "Stopped." This toolkit breaks the workstation into three cost-optimized layers:

1.  **Immutable Environment (Snapshots)**: Your OS, drivers, and `uv/python` environments are baked into "Golden Images." Snapshots are compressed (e.g., a 50GB disk often results in a **10GB snapshot**).
2.  **Ephemeral Compute (Spot GPU)**: High-performance GPUs at Spot rates (~$0.18/hr for T4).
3.  **Active Progress (GCS Sync)**: Large datasets and training outputs are synced to Regional GCS buckets ($0.02/GB) and mapped back to the VM disk on boot.

### The Economics of "Cold Persistence"
For a standard workspace in `europe-west2` (London) with a **10GB OS Snapshot** and **90GB of GCS Data**:

| Persistence Mode | Status | Monthly Cost |
| :--- | :--- | :--- |
| **GCP Always On** | Running 24/7 | **~$129.60** |
| **RunPod/Lambda** | Stopped Pod | ~$20.00 |
| **Traditional GCP** | Stopped VM (Disk only) | ~$10.00 |
| **spot-diffusion** | **Snapshot + GCS** | **~$2.30** |

---

### Internal Lifecycle

1.  **`make up`**: 
    - Finds the latest timestamped Golden Image.
    - Provisions a fresh Spot VM with your configured hardware.
    - Rsyncs your models/datasets from GCS to the local disk.
2.  **`make tunnel`**:
    - Opens an SSH session with multi-port forwarding (Jupyter, WebUIs, Tensorboard) based on `SSH_FORWARDS`.
3.  **`make sync`**:
    - Mid-session push to GCS to save current progress.
4.  **`make down`**:
    - Final Rsync to GCS and **destruction of the VM**. 

### 📋 Prerequisites

Before you begin, ensure you have:
1.  **GCP Account**: A project with billing enabled.
2.  **gcloud CLI**: [Installed](https://cloud.google.com/sdk/docs/install) and authenticated (`gcloud auth login`).
3.  **Project Quota**: Ensure you have GPU quota (e.g., `NVIDIA_T4_GPUS`, `NVIDIA_L4_GPUS`) in your target zone.
4.  **APIs Enabled**: Compute Engine and Cloud Storage APIs must be active.

---

### Getting Started

**1. Configure**
Copy the base environment file and fill in your values.
```bash
cp .env.example .env
vi .env
```

**2. Initialize & Bake**
This one-time process sets up your infrastructure and creates your first "Golden Image."
```bash
make init     # Creates bucket + base VM + setup scripts
make ssh      # Install your tools/libraries (Stable Diffusion, etc.)
make snapshot # Bakes the Golden Image and destroys the VM
```

**3. Daily Productivity**
```bash
make up       # Launch workstation
make tunnel   # Start working with tunnels (7860, etc.)
make down     # Save work to GCS and destroy VM
```

**4. Model Downloader (Cost Optimization)**
To download large models without paying GPU rates, the downloader VM uses
**GCS FUSE mounting** (`gcsfuse`). Directories defined in `SYNC_DIRS` are
mounted directly onto the GCS bucket — anything written to the local path
lands in GCS in real-time with no manual sync step required.
```bash
make dl-up    # Launch a cheap e2-small VM with FUSE-mounted GCS dirs
make dl-ssh   # SSH in and download models (writes go straight to GCS)
make dl-down  # Unmount and destroy the instance
```
> **Note:** `make dl-sync` is a no-op for downloader VMs — it exits early
> with a warning since files are already in GCS via the FUSE mount.

---

### 🌐 Multi-Environment Management

You can maintain multiple environments (e.g., L4 in Seoul vs. T4 in London) by creating multiple `.env` files.

**1. Create a new environment**
```bash
cp .env .env.t4
vi .env.t4 # Update ZONE, MACHINE_TYPE, ACCELERATOR, and VM_NAME
```

**2. Switch environments**
Change the `ENV` variable at the top of the `Makefile`:
```makefile
# Makefile
ENV ?= .env.t4  # Point to your new environment
```
Now all commands (`make up`, `make down`, etc.) will automatically target that environment.

---

### Advanced: Power User Workflows

#### 🔄 Environment Updates (Re-baking)
If you install new system libraries (`apt`) or Python packages globally:
1. `make up`
2. `make ssh` -> install new tools
3. `make snapshot`
The system will create a new timestamped image and use it for all future boots.

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

### Troubleshooting & Logs
- **Initialization**: If `make init` feels slow, SSH in and run `tail -f /var/log/gpu-driver-install.log`.
- **Preemption**: If GCP terminates your Spot VM, your work is safe in GCS up to the last `make sync`. Just run `make up` again.
- **Cleanup**: Delete all cloud resources using `make teardown`.
