# Complete EC2 Setup Guide for PHTS Calculator Workflow

This guide provides a complete setup for running the PHTS calculator workflow on EC2 using Jupyter notebooks.

**Last Updated:** January 28, 2026

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Repository Setup](#repository-setup)
3. [GitHub Credentials Setup](#github-credentials-setup)
4. [Jupyter Notebook Setup](#jupyter-notebook-setup)
5. [Docker Setup (For Lambda Deployment)](#docker-setup-for-lambda-deployment)
6. [Running the Workflow](#running-the-workflow)
7. [Troubleshooting](#troubleshooting)
8. [Script Reference](#script-reference)

---

## Quick Start

### Complete Setup in 3 Steps

```bash
# Step 1: Clone repository and setup Python environment
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/scripts/bash/clone_and_setup.sh
chmod +x clone_and_setup.sh
./clone_and_setup.sh

# Step 2: Setup GitHub credentials (replace YOUR_TOKEN)
cd phts
chmod +x scripts/bash/setup_git_credentials_auto.sh
./scripts/bash/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN

# Step 3: Start Jupyter notebook
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
```

**Connect from Local Machine:**
```bash
# Create SSH tunnel
ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip

# Open browser: http://localhost:8888
# Use token from Jupyter output
```

**Open Calculator Workflow Notebook:**
- Navigate to: `graft-loss/cohort_analysis/calculator/`
- Open: `calculator_workflow.ipynb`

---

## Repository Setup

### Option A: Shallow Clone (Recommended - Faster, Saves Space)

```bash
# Download and run setup script (shallow clone by default)
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/scripts/bash/clone_and_setup.sh
chmod +x clone_and_setup.sh
./clone_and_setup.sh
```

**What it does:**
- ✅ Clones only the latest commit (saves ~50-70% space and time)
- ✅ Detects existing virtual environments (`jupyter-env`, `phts_env`) and uses them
- ✅ Creates new virtual environment only if none exist
- ✅ Installs required dependencies (numpy, pandas, catboost, xgboost, shap, jupyter, etc.)
- ✅ Works if you're already in the repository directory

### Option B: Full Clone (Complete Git History)

If you need full git history (for development, branching, etc.):

```bash
# Download and run full clone script
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/scripts/bash/clone_and_setup_full.sh
chmod +x clone_and_setup_full.sh
./clone_and_setup_full.sh
```

Or manually:
```bash
SHALLOW_CLONE=false ./clone_and_setup.sh
```

### Manual Setup (Step by Step)

```bash
# 1. Clone repository
git clone https://github.com/Jerome3590/phts.git
cd phts

# 2. Setup Python environment
python3 -m venv phts_env
source phts_env/bin/activate

# 3. Install dependencies
pip install --upgrade pip
pip install numpy pandas scikit-learn catboost xgboost shap jupyter matplotlib

# 4. Verify setup
python -c "import numpy, pandas, catboost, xgboost, shap; print('All packages installed')"
```

---

## GitHub Credentials Setup

### Option 1: Automated Script (Recommended)

**Non-Interactive (Recommended):**
```bash
cd phts
chmod +x scripts/bash/setup_git_credentials_auto.sh
./scripts/bash/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN
```

**Interactive:**
```bash
cd phts
chmod +x scripts/bash/setup_git_credentials.sh
./scripts/bash/setup_git_credentials.sh
# Follow prompts
```

### Option 2: Manual Setup

**Method 1: Write Credentials Directly (Easiest)**
```bash
# 1. Configure Git to use credential store
git config --global credential.helper store

# 2. Create/edit credentials file
nano ~/.git-credentials

# 3. Add this line (replace YOUR_TOKEN with your actual PAT):
https://Jerome3590:YOUR_TOKEN@github.com

# 4. Save and exit (Ctrl+X, then Y, then Enter)

# 5. Set proper permissions
chmod 600 ~/.git-credentials
```

**Method 2: Let Git Save Automatically**
```bash
# Configure Git to store credentials permanently
git config --global credential.helper store

# Now when you clone/pull/push, enter your credentials ONCE:
git clone https://github.com/Jerome3590/phts.git
# Username: Jerome3590
# Password: <paste your PAT token>

# Credentials are saved to ~/.git-credentials and won't be asked again
```

**Method 3: One-Line Command (Using sed)**
```bash
# Configure and write credentials in one go
git config --global credential.helper store && \
echo "https://Jerome3590:YOUR_TOKEN@github.com" > ~/.git-credentials && \
chmod 600 ~/.git-credentials
```

**Replace `YOUR_TOKEN` with your actual Personal Access Token.**

### Generate Personal Access Token

1. Go to GitHub.com → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a name (e.g., "EC2 Access")
4. Select scopes:
   - ✅ `repo` (full control of private repositories)
   - ✅ `workflow` (if using GitHub Actions)
5. Click "Generate token"
6. **Copy the token immediately** (you won't see it again!)

### Verify Setup

```bash
# Test Git is working
git --version

# Test GitHub connection
git ls-remote https://github.com/Jerome3590/phts.git
# Should work without prompting for credentials
```

---

## Jupyter Notebook Setup

### Quick Start

```bash
# Activate virtual environment (use existing if available)
cd phts

# Check for existing virtual environment
if [ -d "jupyter-env" ]; then
    source jupyter-env/bin/activate
elif [ -d "phts_env" ]; then
    source phts_env/bin/activate
else
    echo "No virtual environment found. Run clone_and_setup.sh first."
    exit 1
fi

# Start Jupyter (accessible from anywhere)
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

**Note:** The server will display a URL with a token. Copy this URL.

### Connect from Local Machine

**Option A: SSH Tunnel (Recommended - Most Secure)**

On your local machine:

```bash
# Create SSH tunnel
ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip

# Then open in browser:
# http://localhost:8888
# Use the token from the Jupyter server output
```

**Option B: Direct Access (Less Secure)**

If your EC2 security group allows port 8888:

1. Open `http://your-ec2-ip:8888` in your browser
2. Enter the token from the Jupyter server output

### Running Jupyter in Background

**Using screen:**
```bash
screen -S jupyter
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
# Press Ctrl+A then D to detach

# Reattach later
screen -r jupyter
```

**Using tmux:**
```bash
tmux new -s jupyter
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
# Press Ctrl+B then D to detach

# Reattach later
tmux attach -t jupyter
```

### Using the Calculator Workflow Notebook

**Notebook Location:**
```
graft-loss/cohort_analysis/calculator/calculator_workflow.ipynb
```

**Notebook Structure:**
1. **Setup and Configuration** - Paths, dependencies, data checks
2. **Train Models** - Train calculator models for selected cohort(s)
3. **SHAP/FFA Analysis** - Generate causal factors
4. **Inspect Results** - View top factors and importance
5. **Visualizations** - Plot results (optional)
6. **Export Summary** - Create summary JSON
7. **Deploy Dashboard** - Deploy to AWS Lambda and S3

**Configuration:**
```python
DEBUG_MODE = False  # True for quick testing
COHORT = "Combined"  # Single model approach
TOP_K = 10  # Number of top causal factors
WEIGHT_CATBOOST = None  # Auto-determined from best model
WEIGHT_XGBOOST = None   # Auto-determined from best model
```

**Expected Runtime:**
- Setup/Checks: < 1 minute
- Model Training (per model): 15-30 minutes
- SHAP/FFA (per model): 10-20 minutes
- Total (both models): ~50-100 minutes

---

## Docker Setup (For Lambda Deployment)

If you need to deploy the risk calculator to AWS Lambda, you'll need Docker installed.

### Quick Installation

**Amazon Linux 2:**
```bash
sudo yum update -y
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user
newgrp docker  # Or log out and back in
docker --version  # Verify
```

**Amazon Linux 2023:**
```bash
sudo dnf update -y
sudo dnf install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user
newgrp docker  # Or log out and back in
docker --version  # Verify
```

**Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ubuntu
newgrp docker  # Or log out and back in
docker --version  # Verify
```

### Fix Docker Permissions

If you get a "permission denied" error when building Docker images:

```bash
# Add your user to docker group
sudo usermod -aG docker $USER

# Apply the group changes (choose one):
# Option 1: Log out and log back in (recommended)
# Option 2: Run this command in your current session:
newgrp docker

# Verify it worked:
groups | grep docker
docker ps
```

**Note:** After adding your user to the docker group, you must log out and back in (or run `newgrp docker`) for the changes to take effect.

### Docker for AWS ECR

To push images to AWS ECR, you need AWS CLI installed. **If your EC2 instance has an IAM role attached, credentials are automatically provided** - no need to run `aws configure`.

```bash
# Install AWS CLI (if not already installed)
# Amazon Linux 2
sudo yum install aws-cli -y

# Amazon Linux 2023
sudo dnf install awscli -y

# Ubuntu
sudo apt-get install awscli -y

# Test AWS CLI (uses EC2 instance role credentials automatically)
aws sts get-caller-identity

# If this works, you're all set! No need to run aws configure.
# If it fails, you may need to:
# 1. Attach an IAM role to your EC2 instance with ECR permissions, OR
# 2. Run: aws configure (and enter credentials manually)
```

### Login to ECR

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

### Using Docker for Lambda Deployment

Once Docker is installed, you can build and push Lambda container images:

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard

# Build and push Docker image
./docker_build_phts.sh

# This will:
# 1. Prepare lambda directory
# 2. Build Docker image
# 3. Push to ECR
# 4. Output ECR URI for Lambda update
```

---

## Running the Workflow

### Interactive Mode (Recommended - Jupyter Notebook)

1. Start Jupyter: `jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser`
2. Connect via SSH tunnel from local machine
3. Open `calculator_workflow.ipynb` in browser
4. Run cells step by step or use "Run All"

### Command Line Mode

```bash
# Activate environment
source phts_env/bin/activate

# Navigate to calculator directory
cd graft-loss/cohort_analysis/calculator

# Train models
python train_python_models.py --cohort Combined

# Run SHAP/FFA analysis
python run_shap_ffa_workflow.py --cohort Combined --top-k 10 --model-variant base
python run_shap_ffa_workflow.py --cohort Combined --top-k 10 --model-variant enhanced
```

---

## Troubleshooting

### Repository Setup Issues

**Problem:** Clone fails with authentication error
```bash
# Solution: Setup credentials first
./scripts/bash/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN
```

**Problem:** Virtual environment creation fails
```bash
# Solution: Check Python version
python3 --version  # Should be 3.8+
# Reinstall Python if needed
```

### GitHub Credentials Issues

**Problem:** Still being prompted for credentials
```bash
# Check if credential helper is set
git config --global credential.helper

# If empty, set it:
git config --global credential.helper store

# Check if credentials file exists
ls -la ~/.git-credentials

# If it exists but still prompts, check permissions
chmod 600 ~/.git-credentials
```

**Problem:** Token not working
```bash
# Solution: Verify token has 'repo' scope
# Check: https://github.com/settings/tokens
```

### Jupyter Notebook Issues

**Problem:** Jupyter not starting
```bash
# Check if port is in use
netstat -tuln | grep 8888

# Use different port
jupyter notebook --ip=0.0.0.0 --port=8889 --no-browser
```

**Problem:** Can't connect from browser
1. Check SSH tunnel: Make sure tunnel is active
2. Check EC2 Security Group: Port 8888 must be open (if direct access)
3. Check Jupyter is running: `ps aux | grep jupyter`
4. Check token: Use the token from Jupyter output

**Problem:** Import errors in notebook
```bash
# Make sure you're in the virtual environment
source phts_env/bin/activate

# Install missing packages
pip install <package_name>

# Restart Jupyter kernel
# In notebook: Kernel > Restart
```

**Problem:** Kernel dies
```bash
# Check memory usage
free -h

# Check disk space
df -h

# Restart with more memory (if needed)
# Consider using a larger EC2 instance
```

### Docker Issues

**Problem:** Permission denied while trying to connect to Docker daemon
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or:
newgrp docker

# Verify
docker ps
```

**Problem:** Docker service not running
```bash
# Start Docker service
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker

# Check status
sudo systemctl status docker
```

**Problem:** ECR login fails
```bash
# Verify AWS CLI is configured
aws sts get-caller-identity

# If fails, attach IAM role to EC2 instance with ECR permissions
# Or run: aws configure
```

**Problem:** Docker build fails (out of memory)
```bash
# Check available disk space
df -h

# Check available memory
free -h

# Clean up Docker
docker system prune -a

# Use larger EC2 instance if needed (e.g., t3.large or larger)
```

### Data File Issues

**Problem:** Data file not found
```bash
# The workflow requires: graft-loss/data/phts_txpl_ml.sas7bdat
# Make sure:
# - The data file is in the correct location
# - You have read permissions
# - The file is not corrupted
```

---

## Script Reference

### Available Scripts

| Script | Purpose | Location | When to Use |
|--------|---------|----------|-------------|
| `clone_and_setup.sh` | Clone repo + setup Python env (shallow) | `scripts/bash/` | **Recommended** - First-time setup, faster |
| `clone_and_setup_full.sh` | Clone repo + setup Python env (full history) | `scripts/bash/` | If you need full git history |
| `setup_git_credentials.sh` | Interactive GitHub PAT setup | `scripts/bash/` | First-time credential setup (interactive) |
| `setup_git_credentials_auto.sh` | Non-interactive GitHub PAT setup | `scripts/bash/` | **Recommended** - Automated credential setup |
| `calculator_workflow.ipynb` | Jupyter notebook for calculator workflow | `graft-loss/cohort_analysis/calculator/` | **Recommended** - Interactive workflow on EC2 |

### Direct Script Links (GitHub Raw)

- `clone_and_setup.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/scripts/bash/clone_and_setup.sh
- `clone_and_setup_full.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/scripts/bash/clone_and_setup_full.sh
- `setup_git_credentials.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/scripts/bash/setup_git_credentials.sh
- `setup_git_credentials_auto.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/scripts/bash/setup_git_credentials_auto.sh

---

## Verification Checklist

After setup, verify:

- [ ] Repository cloned: `ls ~/phts`
- [ ] Virtual environment exists: `ls ~/phts/phts_env`
- [ ] Python packages installed: `python -c "import numpy, pandas, catboost, xgboost, shap"`
- [ ] Git credentials configured: `git pull` (should not prompt)
- [ ] Jupyter installed: `jupyter --version`
- [ ] Jupyter can start: `jupyter notebook --help`
- [ ] Docker installed (if needed): `docker --version`
- [ ] Docker permissions (if needed): `docker ps`
- [ ] AWS CLI configured (if needed): `aws sts get-caller-identity`
- [ ] Data file exists: `ls graft-loss/data/phts_txpl_ml.sas7bdat`

---

## Security Best Practices

1. **Use SSH tunnel** for Jupyter instead of exposing directly
2. **Set Jupyter password** for additional security: `jupyter notebook password`
3. **Use token authentication** (Jupyter generates automatically)
4. **Limit EC2 Security Group** to your IP address only
5. **Use SSH keys** instead of HTTPS tokens when possible
6. **Set passphrase** on SSH keys
7. **Rotate tokens/keys** periodically
8. **Never commit credentials** to the repository

---

## Quick Reference

**Start Jupyter:**
```bash
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
```

**SSH Tunnel (local machine):**
```bash
ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip
```

**Access in Browser:**
```
http://localhost:8888/?token=YOUR_TOKEN
```

**Notebook Location:**
```
graft-loss/cohort_analysis/calculator/calculator_workflow.ipynb
```

**Docker Commands:**
```bash
# Install Docker (Amazon Linux 2)
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user
newgrp docker

# Test Docker
docker --version
docker run hello-world
```

---

## Additional Resources

- **Calculator Workflow Documentation:** `graft-loss/cohort_analysis/calculator/README.md`
- **SHAP/FFA Workflow:** `graft-loss/cohort_analysis/calculator/README_SHAP_FFA.md`
- **Deployment Guide:** `graft-loss/cohort_analysis/calculator/risk_dashboard/README_DEPLOYMENT.md`
- **Main Project README:** `README.md`

---

**Last Updated:** January 28, 2026
