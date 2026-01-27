# Jupyter Notebook Setup on EC2

This guide explains how to set up and run Jupyter notebooks on EC2 for the PHTS calculator workflow.

## Quick Start

### 1. Clone Repository and Setup

**Option A: Shallow Clone (Recommended - Faster, Saves Space)**

```bash
# Download and run setup script (shallow clone by default)
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup.sh
chmod +x clone_and_setup.sh
./clone_and_setup.sh
```

This clones only the latest commit (saves ~50-70% space and time).

**Option B: Full Clone (Complete Git History)**

```bash
# Download and run full clone script
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup_full.sh
chmod +x clone_and_setup_full.sh
./clone_and_setup_full.sh
```

Or manually:
```bash
# Force full clone
SHALLOW_CLONE=false ./clone_and_setup.sh
```

### 2. Setup GitHub Credentials

```bash
cd phts
chmod +x docs/setup_git_credentials_auto.sh
./docs/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN
```

### 3. Start Jupyter Notebook Server

```bash
# Activate virtual environment
cd phts
source phts_env/bin/activate

# Start Jupyter (accessible from anywhere)
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root
```

**Note:** The server will display a URL with a token. Copy this URL.

### 4. Connect from Local Machine

**Option A: SSH Tunnel (Recommended)**

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

### 5. Open Calculator Workflow Notebook

In Jupyter:
1. Navigate to `graft-loss/cohort_analysis/calculator/`
2. Open `calculator_workflow.ipynb`
3. Run cells step by step or use "Run All"

---

## Detailed Setup

### Install Jupyter

```bash
# Activate virtual environment
source phts_env/bin/activate

# Install Jupyter
pip install jupyter notebook

# Or install JupyterLab (more features)
pip install jupyterlab
```

### Configure Jupyter

```bash
# Generate Jupyter config
jupyter notebook --generate-config

# Set password (optional, more secure than token)
jupyter notebook password
```

### Start Jupyter with Custom Settings

```bash
# Create a startup script
cat > start_jupyter.sh << 'EOF'
#!/bin/bash
source ~/phts/phts_env/bin/activate
cd ~/phts
jupyter notebook \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --notebook-dir=~/phts \
    --allow-root
EOF

chmod +x start_jupyter.sh
```

### Run Jupyter in Background (with screen/tmux)

```bash
# Using screen
screen -S jupyter
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
# Press Ctrl+A then D to detach

# Reattach later
screen -r jupyter

# Using tmux
tmux new -s jupyter
source phts_env/bin/activate
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
# Press Ctrl+B then D to detach

# Reattach later
tmux attach -t jupyter
```

---

## Security Best Practices

### 1. Use SSH Tunnel (Recommended)

Always use SSH tunneling instead of exposing Jupyter directly:

```bash
# On local machine
ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip
```

### 2. Set Jupyter Password

```bash
jupyter notebook password
# Enter a strong password when prompted
```

### 3. Use Token Authentication

Jupyter automatically generates a token. Always use it:

```bash
# The token appears in the Jupyter server output:
# http://localhost:8888/?token=abc123...
```

### 4. Restrict IP Access (If Direct Access Needed)

In EC2 Security Group:
- Only allow port 8888 from your IP address
- Or use a VPN

### 5. Use HTTPS (Production)

For production, set up HTTPS with a reverse proxy (nginx) and SSL certificate.

---

## Using the Calculator Workflow Notebook

### Notebook Structure

The `calculator_workflow.ipynb` notebook contains:

1. **Setup and Configuration** - Paths, dependencies, data checks
2. **Train Models** - Train calculator models for selected cohort(s)
3. **SHAP/FFA Analysis** - Generate causal factors
4. **Inspect Results** - View top factors and importance
5. **Visualizations** - Plot results (optional)
6. **Export Summary** - Create summary JSON
7. **Quick Run All Cohorts** - Complete workflow for all cohorts

### Configuration

Edit the configuration cell to set:

```python
DEBUG_MODE = False  # True for quick testing
COHORTS = ["Combined"]  # Or ["Combined", "CHD", "Myocardio"]
TOP_K = 10  # Number of top causal factors
WEIGHT_CATBOOST = 0.6  # CatBoost importance weight
WEIGHT_XGBOOST = 0.4  # XGBoost importance weight
```

### Running the Notebook

**Option 1: Run All Cells**
- `Cell > Run All` - Runs entire notebook

**Option 2: Run Step by Step**
- Click each cell and press `Shift+Enter`
- Or use the "Run" button in toolbar

**Option 3: Run Selected Cells**
- Select multiple cells (Shift+Click)
- `Cell > Run Cells`

### Expected Runtime

- **Setup/Checks**: < 1 minute
- **Model Training (per cohort)**: 10-30 minutes
- **SHAP/FFA (per cohort)**: 5-15 minutes
- **Results Inspection**: < 1 minute
- **Total (all 3 cohorts)**: ~1-2 hours

---

## Troubleshooting

### Jupyter Not Starting

```bash
# Check if port is in use
netstat -tuln | grep 8888

# Use different port
jupyter notebook --ip=0.0.0.0 --port=8889 --no-browser
```

### Can't Connect from Browser

1. **Check SSH tunnel**: Make sure tunnel is active
2. **Check EC2 Security Group**: Port 8888 must be open (if direct access)
3. **Check Jupyter is running**: `ps aux | grep jupyter`
4. **Check token**: Use the token from Jupyter output

### Import Errors in Notebook

```bash
# Make sure you're in the virtual environment
source phts_env/bin/activate

# Install missing packages
pip install <package_name>

# Restart Jupyter kernel
# In notebook: Kernel > Restart
```

### Kernel Dies

```bash
# Check memory usage
free -h

# Check disk space
df -h

# Restart with more memory (if needed)
# Consider using a larger EC2 instance
```

### Notebook Not Found

```bash
# Make sure you're in the right directory
cd ~/phts/graft-loss/cohort_analysis/calculator

# List notebooks
ls *.ipynb
```

---

## Alternative: JupyterLab

JupyterLab provides a more modern interface:

```bash
# Install JupyterLab
pip install jupyterlab

# Start JupyterLab
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser
```

JupyterLab features:
- File browser
- Terminal integration
- Multiple notebooks
- Extensions and plugins

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

---

**Last Updated**: January 26, 2026
