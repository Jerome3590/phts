# EC2 Script Plan - Complete Reference

This document provides a comprehensive overview of all scripts available for EC2 setup and workflow execution.

## 📋 Scripts Overview

| Script | Purpose | Location | When to Use |
|--------|---------|----------|-------------|
| `clone_and_setup.sh` | Clone repo + setup Python env (shallow) | `docs/` | **Recommended** - First-time setup, faster |
| `clone_and_setup_full.sh` | Clone repo + setup Python env (full history) | `docs/` | If you need full git history |
| `setup_git_credentials.sh` | Interactive GitHub PAT setup | `docs/` | First-time credential setup (interactive) |
| `setup_git_credentials_auto.sh` | Non-interactive GitHub PAT setup | `docs/` | **Recommended** - Automated credential setup |
| `calculator_workflow.ipynb` | Jupyter notebook for calculator workflow | `graft-loss/cohort_analysis/calculator/` | **Recommended** - Interactive workflow on EC2 |
| `calculator_workflow_interactive.py` | VS Code interactive Python script | `docs/` | Alternative - VS Code Python Interactive window |

---

## 🚀 Quick Start Workflow

### Step 1: Clone Repository and Setup Environment

**Option A: Shallow Clone (Recommended)**
```bash
# Download and run
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup.sh
chmod +x clone_and_setup.sh
./clone_and_setup.sh
```

**Option B: Full Clone (If needed)**
```bash
# Download and run
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup_full.sh
chmod +x clone_and_setup_full.sh
./clone_and_setup_full.sh
```

**What it does:**
- ✅ Checks/installs Git
- ✅ Clones repository (shallow or full)
- ✅ Checks/installs Python 3
- ✅ Creates virtual environment (`phts_env`)
- ✅ Upgrades pip
- ✅ Installs dependencies (numpy, pandas, catboost, xgboost, shap, jupyter, matplotlib)

**Output:**
- Repository at: `~/phts/`
- Virtual environment at: `~/phts/phts_env/`

---

### Step 2: Setup GitHub Credentials

**Option A: Automated (Recommended)**
```bash
cd phts
chmod +x docs/setup_git_credentials_auto.sh
./docs/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN
```

**Option B: Interactive**
```bash
cd phts
chmod +x docs/setup_git_credentials.sh
./docs/setup_git_credentials.sh
# Follow prompts
```

**What it does:**
- ✅ Configures Git credential helper
- ✅ Stores PAT token in `~/.git-credentials`
- ✅ Sets proper file permissions (600)
- ✅ Tests connection

**Result:** Git won't prompt for credentials anymore

---

### Step 3: Start Jupyter Notebook

```bash
cd phts
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

**Open Notebook:**
- Navigate to: `graft-loss/cohort_analysis/calculator/`
- Open: `calculator_workflow.ipynb`

---

## 📝 Detailed Script Documentation

### 1. `clone_and_setup.sh`

**Purpose:** Clone repository and setup Python environment (shallow clone by default)

**Usage:**
```bash
# Default (shallow clone)
./clone_and_setup.sh

# Force full clone
SHALLOW_CLONE=false ./clone_and_setup.sh
```

**Features:**
- ✅ Auto-detects and installs Git if missing
- ✅ Auto-detects and installs Python 3 if missing
- ✅ Shallow clone by default (saves ~50-70% space/time)
- ✅ Creates virtual environment
- ✅ Installs all required packages
- ✅ Handles existing repository (pulls updates)

**Dependencies Installed:**
- numpy, pandas, scikit-learn
- catboost, xgboost
- shap
- jupyter, notebook
- matplotlib

**Output Directory:**
- `~/phts/` (or current directory)

---

### 2. `clone_and_setup_full.sh`

**Purpose:** Clone repository with full git history

**Usage:**
```bash
./clone_and_setup_full.sh
```

**Features:**
- Same as `clone_and_setup.sh` but always does full clone
- Includes complete git history
- Useful for development, branching, git operations

**When to Use:**
- Need full git history
- Planning to create branches
- Need to access older commits
- Development work

---

### 3. `setup_git_credentials.sh`

**Purpose:** Interactive script to setup GitHub credentials

**Usage:**
```bash
chmod +x docs/setup_git_credentials.sh
./docs/setup_git_credentials.sh
```

**Features:**
- ✅ Prompts for username
- ✅ Prompts for PAT token (hidden input)
- ✅ Validates inputs
- ✅ Configures credential helper
- ✅ Tests connection
- ✅ Provides feedback

**Interactive Flow:**
1. Prompts: "Enter your GitHub username:"
2. Prompts: "Enter your GitHub Personal Access Token:" (hidden)
3. Configures Git
4. Tests connection
5. Reports success/failure

---

### 4. `setup_git_credentials_auto.sh`

**Purpose:** Non-interactive script to setup GitHub credentials

**Usage:**
```bash
# With arguments
./docs/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN

# With environment variables
GITHUB_USERNAME=Jerome3590 GITHUB_TOKEN=YOUR_TOKEN ./docs/setup_git_credentials_auto.sh
```

**Features:**
- ✅ No prompts - fully automated
- ✅ Accepts arguments or environment variables
- ✅ Uses `sed` for cross-platform compatibility
- ✅ Handles existing credentials (removes old, adds new)
- ✅ Sets proper permissions

**When to Use:**
- ✅ Automation scripts
- ✅ CI/CD pipelines
- ✅ Non-interactive environments
- ✅ Quick setup

---

### 5. `calculator_workflow.ipynb`

**Purpose:** Jupyter notebook for interactive calculator workflow

**Location:** `graft-loss/cohort_analysis/calculator/calculator_workflow.ipynb`

**Usage:**
1. Start Jupyter: `jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser`
2. Open in browser (via SSH tunnel)
3. Navigate to notebook
4. Run cells step by step or "Run All"

**Notebook Sections:**
1. **Setup and Configuration** - Paths, dependencies, data checks
2. **Train Calculator Models** - Train models for selected cohorts
3. **Run SHAP + FFA Analysis** - Generate causal factors
4. **Inspect Results** - View top factors and importance
5. **Visualizations** - Plot results (optional)
6. **Export Summary** - Create summary JSON
7. **Quick Run All Cohorts** - Complete workflow for all cohorts

**Configuration:**
```python
DEBUG_MODE = False  # True for quick testing
COHORTS = ["Combined"]  # Or ["Combined", "CHD", "Myocardio"]
TOP_K = 10  # Number of top causal factors
WEIGHT_CATBOOST = 0.6  # CatBoost importance weight
WEIGHT_XGBOOST = 0.4  # XGBoost importance weight
```

**Expected Runtime:**
- Setup/Checks: < 1 minute
- Model Training (per cohort): 10-30 minutes
- SHAP/FFA (per cohort): 5-15 minutes
- Total (all 3 cohorts): ~1-2 hours

---

### 6. `calculator_workflow_interactive.py`

**Purpose:** VS Code Python Interactive window script (alternative to Jupyter)

**Location:** `docs/calculator_workflow_interactive.py`

**Usage:**
1. Open in VS Code
2. Select Python interpreter (virtual environment)
3. Click "Run Cell" above each `# %%` marker
4. Or use `Ctrl+Enter` to run current cell

**Features:**
- ✅ Cell-based execution (`# %%` markers)
- ✅ Interactive debugging
- ✅ Visual output (plots, data viewers)
- ✅ Variables Explorer
- ✅ Same workflow as Jupyter notebook

**When to Use:**
- ✅ VS Code user
- ✅ Prefer VS Code interface
- ✅ Want integrated debugging
- ✅ Already using VS Code Remote-SSH

---

## 🔄 Complete Workflow Examples

### Example 1: First-Time EC2 Setup (Recommended)

```bash
# 1. Clone and setup
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup.sh
chmod +x clone_and_setup.sh
./clone_and_setup.sh

# 2. Setup credentials
cd phts
chmod +x docs/setup_git_credentials_auto.sh
./docs/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN

# 3. Start Jupyter
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser

# 4. On local machine: SSH tunnel
# ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip

# 5. Open browser: http://localhost:8888
# 6. Navigate to: graft-loss/cohort_analysis/calculator/calculator_workflow.ipynb
```

---

### Example 2: Quick Setup (All in One)

```bash
# Download all scripts
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup.sh
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/setup_git_credentials_auto.sh

# Make executable
chmod +x clone_and_setup.sh setup_git_credentials_auto.sh

# Run setup
./clone_and_setup.sh

# Setup credentials (replace YOUR_TOKEN)
cd phts
./setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN

# Start Jupyter
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
```

---

### Example 3: Command Line Workflow (No Jupyter)

```bash
# After setup
cd phts
source phts_env/bin/activate

# Train models
cd graft-loss/cohort_analysis/calculator
python train_python_models.py --cohort Combined

# Run SHAP/FFA
python run_shap_ffa_workflow.py --cohort Combined --top-k 10
```

---

## 📊 Script Comparison

| Feature | `clone_and_setup.sh` | `clone_and_setup_full.sh` |
|---------|---------------------|--------------------------|
| Clone Type | Shallow (default) | Full |
| Space Used | ~50-70% less | Full |
| Clone Time | Faster | Slower |
| Git History | Latest commit only | Complete history |
| Use Case | Running workflow | Development |

| Feature | `setup_git_credentials.sh` | `setup_git_credentials_auto.sh` |
|---------|-------------------------|-------------------------------|
| Interaction | Interactive prompts | Non-interactive |
| Input Method | Prompts | Arguments/env vars |
| Use Case | Manual setup | Automation |
| Error Handling | User-friendly | Exit on error |

| Feature | `calculator_workflow.ipynb` | `calculator_workflow_interactive.py` |
|---------|---------------------------|-----------------------------------|
| Interface | Jupyter notebook | VS Code Interactive |
| Platform | Browser-based | VS Code |
| Execution | Cell-by-cell | Cell-by-cell |
| Best For | EC2 Jupyter | VS Code Remote-SSH |

---

## 🛠️ Troubleshooting

### Clone Script Issues

**Problem:** Clone fails with authentication error
```bash
# Solution: Setup credentials first
./docs/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN
```

**Problem:** Shallow clone but need full history later
```bash
# Solution: Convert to full clone
cd phts
git fetch --unshallow
```

**Problem:** Virtual environment creation fails
```bash
# Solution: Check Python version
python3 --version  # Should be 3.8+
# Reinstall Python if needed
```

---

### Credential Script Issues

**Problem:** Token not working
```bash
# Solution: Verify token has 'repo' scope
# Check: https://github.com/settings/tokens
```

**Problem:** Credentials file permissions
```bash
# Solution: Fix permissions
chmod 600 ~/.git-credentials
```

**Problem:** sed command fails (macOS)
```bash
# Solution: Script handles this automatically
# Uses: sed -i '' for macOS, sed -i for Linux
```

---

### Jupyter Notebook Issues

**Problem:** Can't connect from browser
```bash
# Solution: Check SSH tunnel
# Make sure tunnel is active: ssh -i key.pem -L 8888:localhost:8888 user@ip
# Check Jupyter is running: ps aux | grep jupyter
```

**Problem:** Import errors in notebook
```bash
# Solution: Make sure virtual environment is activated
source phts_env/bin/activate
# Restart Jupyter kernel
```

**Problem:** Port already in use
```bash
# Solution: Use different port
jupyter notebook --ip=0.0.0.0 --port=8889 --no-browser
```

---

## 📚 Additional Resources

- **Complete Setup Guide:** `docs/EC2_SETUP_COMPLETE.md`
- **Jupyter Setup:** `docs/EC2_JUPYTER_SETUP.md`
- **GitHub Credentials:** `docs/EC2_GITHUB_SETUP.md`
- **Quick Credentials:** `docs/EC2_GITHUB_SETUP_QUICK.md`
- **Calculator Workflow:** `graft-loss/cohort_analysis/calculator/README_SHAP_FFA.md`

---

## 🔗 Direct Script Links (GitHub Raw)

- `clone_and_setup.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup.sh
- `clone_and_setup_full.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup_full.sh
- `setup_git_credentials.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/docs/setup_git_credentials.sh
- `setup_git_credentials_auto.sh`: https://raw.githubusercontent.com/Jerome3590/phts/main/docs/setup_git_credentials_auto.sh

---

**Last Updated:** January 26, 2026
