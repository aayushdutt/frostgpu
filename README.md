# spot-diffusion

Zero idle cost Stable Diffusion on GCP Spot T4 GPUs. VMs are destroyed after every session and restored from a snapshot — you only pay while generating.

**Cost:** ~$0.12/hr compute + $0.05/GB snapshots + $0.02/GB GCS. Roughly $6/month at ~1hr/day.

---

### Architecture

| Layer | What | Cost |
|-------|------|------|
| Compute | Spot T4 (`n1-standard-4`) | ~$0.12/hr |
| State | Regional snapshot (offline disk) | $0.05/GB |
| Storage | GCS bucket (models + outputs) | $0.02/GB |
| Access | SSH tunnel on port 7860 | Free |

---

### Setup (one-time)

**1.** Copy the example config and fill in your GCP details:

```bash
cp config.mk.example config.mk
# Edit config.mk: set PROJECT_ID, BUCKET, ZONE, VM_NAME, etc.
```

**2.** Add your SSH public key to `scripts/cloud-init.yaml`, then:

```bash
make init       # Creates bucket + base VM, installs Nvidia drivers (~10 min)
make ssh        # Shell into the VM
```

**3.** Inside the VM:

```bash
sudo fallocate -l 16G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab && sudo swapon -a
git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
cd stable-diffusion-webui && ./webui.sh --xformers --exit
exit
```

**4.** Bake the golden image:

```bash
make snapshot   # Saves OS + drivers + venv, destroys VM
```

---

### Daily Workflow

```bash
make up         # Restore VM from snapshot, sync models from GCS
make ui         # Open SSH tunnel → run ./webui.sh --xformers inside VM
# Open http://localhost:7860
make down       # Sync outputs/models to GCS, destroy VM
```

---

### Reference

| Command | What it does |
|---------|-------------|
| `make init` | First-time setup: bucket + base VM |
| `make up` | Restore VM + sync models |
| `make down` | Sync outputs + destroy VM |
| `make snapshot` | Rebake golden image + destroy VM |
| `make ssh` | Plain SSH into VM |
| `make ui` | SSH tunnel for WebUI (port 7860) |

- **Add models:** Upload `.safetensors` to `gs://your-bucket/models/`
- **Update WebUI:** `make up` → `git pull` → `make snapshot`
- **Keep VM, snapshot, and bucket in the same region** to avoid egress fees
