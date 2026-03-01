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
    - Opens an SSH session with multi-port forwarding (Jupyter, WebUIs, Tensorboard) based on `config.mk`.
3.  **`make sync`**:
    - Mid-session push to GCS to save current progress.
4.  **`make down`**:
    - Final Rsync to GCS and **destruction of the VM**. 

### 📋 Prerequisites

Before you begin, ensure you have:
1.  **GCP Account**: A project with billing enabled.
2.  **gcloud CLI**: [Installed](https://cloud.google.com/sdk/docs/install) and authenticated.
    ```bash
    gcloud auth login
    ```
3.  **Project Quota**: Ensure you have GPU quota (e.g., `NVIDIA_T4_GPUS`) in your target zone.
4.  **APIs Enabled**: Compute Engine and Cloud Storage APIs must be active.

---

### Getting Started

**1. Configure**
```bash
cp config.mk.example config.mk
vi config.mk
```

**2. Initialize & Bake**
This one-time process sets up your infrastructure and creates your first "Golden Image."
```bash
make init     # Creates bucket + base VM + vm setup script (reboot if needed after first launch)
make ssh      # Install your tools/libraries
make snapshot # Bakes the Golden Image and destroys the VM
```

**3. Daily Productivity**
```bash
make up       # Launch workstation
make tunnel   # Start working with tunnels (7860, 8888, etc.)
make down     # Save work to GCS (optional) and destroy VM
```

---

### Advanced: Power User Workflows

#### ⚡️ Hardware Scaling
You aren't locked into T4s. Modify `config.mk` to swap to L4s or A100s for a single session:
```makefile
MACHINE_TYPE  = g2-standard-4
ACCELERATOR   = count=1,type=nvidia-l4
```
Run `make up` and your existing OS/Software snapshot will boot onto the new hardware.

#### 🔄 Environment Updates (Re-baking)
If you install new system libraries (`apt`) or Python packages globally:
1. `make up`
2. `make ssh` -> install new tools
3. `make snapshot`
The system will create a new timestamped image and use it for all future boots.

#### 🔌 Arbitrary Port Tunneling
Define ports in `config.mk` to open them during `make tunnel`:
```makefile
SSH_FORWARDS = 8888:8888 6006:6006 7860:7860
```

#### 📂 Directory Syncing
Map VM directories to GCS subdirectories:
```makefile
SYNC_DIRS = ~/models:models ~/outputs:outputs
```

---

### Troubleshooting & Logs
- **Initialization**: If `make init` feels slow, SSH in and run `tail -f /var/log/gpu-driver-install.log`.
- **Preemption**: If GCP terminates your Spot VM, your work is safe in GCS up to the last `make sync`. Just run `make up` again.
- **Cleanup**: Delete all cloud resources using `make teardown`.
