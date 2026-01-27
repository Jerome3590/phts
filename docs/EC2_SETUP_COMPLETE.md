# Complete EC2 Setup Guide

This guide provides a complete setup for running the PHTS calculator workflow on EC2.

## Quick Start

### 1. Clone Repository and Setup

**Option A: Shallow Clone (Recommended - Faster, Saves Space)**

```bash
# Download and run setup script (shallow clone by default)
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup.sh
chmod +x clone_and_setup.sh
./clone_and_setup.sh
```

This clones only the latest commit (saves ~50-70% space and time). Perfect for running the calculator workflow.

**Option B: Full Clone (Complete Git History)**

If you need full git history (for development, branching, etc.):

```bash
# Download and run full clone script
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/clone_and_setup_full.sh
chmod +x clone_and_setup_full.sh
./clone_and_setup_full.sh
```

Or manually:
```bash
SHALLOW_CLONE=false ./clone_and_setup.sh
```

**What the script does:**
- Clone the repository (shallow or full)
- **Detects existing virtual environments** (`jupyter-env`, `phts_env`) and uses them
- Creates new virtual environment only if none exist
- Install required dependencies (numpy, pandas, catboost, xgboost, shap, jupyter, etc.)
- Works if you're already in the repository directory

### 2. Configure GitHub Credentials

```bash
# Run the credential setup script
cd phts
chmod +x docs/setup_git_credentials.sh
./docs/setup_git_credentials.sh

# Or use the non-interactive version
./docs/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN
```

### 3. Start Jupyter Notebook

```bash
# Activate virtual environment
source phts_env/bin/activate

# Start Jupyter server
jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser
```

**Connect from Local Machine:**

On your local machine, create SSH tunnel:
```bash
ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip
```

Then open in browser: `http://localhost:8888` (use token from Jupyter output)

**Open Calculator Workflow Notebook:**
- Navigate to `graft-loss/cohort_analysis/calculator/`
- Open `calculator_workflow.ipynb`
- Run cells step by step or use "Run All"

**Option B: Run Individual Scripts**

```bash
# Activate virtual environment
cd phts
source phts_env/bin/activate

# Train models
cd graft-loss/cohort_analysis/calculator
python train_python_models.py --cohort Combined

# Run SHAP/FFA analysis
python run_shap_ffa_workflow.py --cohort Combined --top-k 10
```

## Interactive Workflow Script

The `calculator_workflow_interactive.py` script is designed to work with VS Code's Python Interactive window. It uses `# %%` cell delimiters that VS Code recognizes.

### Features

- **Cell-based execution**: Run code step by step
- **Interactive debugging**: Set breakpoints and inspect variables
- **Visual output**: Plots and data viewers work in the interactive window
- **Variable exploration**: Use Variables Explorer to inspect data

### Cell Structure

1. **Setup and Imports** - Initialize paths and logging
2. **Configuration** - Set cohort, top-k, weights
3. **Check Dependencies** - Verify packages are installed
4. **Check Data Availability** - Verify data files exist
5. **Train Models** - Train calculator models
6. **Check Training Results** - Inspect model outputs
7. **Run SHAP/FFA Workflow** - Execute analysis
8. **Inspect Results** - View causal factors and importance
9. **Load Feature Importance** - Display importance rankings
10. **Quick Training (All Cohorts)** - Train all models at once
11. **Quick SHAP/FFA (All Cohorts)** - Run analysis for all cohorts
12. **Export Results Summary** - Create summary JSON

### Usage in VS Code

1. **Open the file**: `docs/calculator_workflow_interactive.py`
2. **Select interpreter**: Choose the virtual environment Python
3. **Run cells**: 
   - Click "Run Cell" above each `# %%` marker
   - Or use `Ctrl+Enter` to run current cell
   - Or use `Shift+Enter` to run and move to next cell

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Run Cell | `Ctrl+Enter` |
| Run Cell and Move to Next | `Shift+Enter` |
| Go to Next Cell | `Ctrl+Alt+]` |
| Go to Previous Cell | `Ctrl+Alt+[` |
| Insert Cell Below | `Ctrl+; B` |
| Delete Cell | `Ctrl+; X` |

## Manual Setup (Step by Step)

### 1. Clone Repository

```bash
git clone https://github.com/Jerome3590/phts.git
cd phts
```

### 2. Setup Python Environment

```bash
# Create virtual environment
python3 -m venv phts_env

# Activate
source phts_env/bin/activate

# Install dependencies
pip install --upgrade pip
pip install numpy pandas scikit-learn catboost xgboost shap jupyter
```

### 3. Verify Setup

```bash
# Check Python
python --version

# Check packages
python -c "import numpy, pandas, catboost, xgboost, shap; print('All packages installed')"
```

## Running the Workflow

### Interactive Mode (Recommended)

1. Open `docs/calculator_workflow_interactive.py` in VS Code
2. Run cells step by step
3. Inspect results in Variables Explorer
4. View plots in Plot Viewer

### Command Line Mode

```bash
# Activate environment
source phts_env/bin/activate

# Navigate to calculator directory
cd graft-loss/cohort_analysis/calculator

# Train models
python train_python_models.py --cohort Combined

# Run analysis
python run_shap_ffa_workflow.py --cohort Combined --top-k 10
```

## Troubleshooting

### VS Code Python Interactive Window Not Working

1. **Install Python extension**: Make sure Python extension is installed
2. **Select interpreter**: Use `Ctrl+Shift+P` → "Python: Select Interpreter"
3. **Install Jupyter**: `pip install jupyter` in your virtual environment
4. **Check cell markers**: Ensure `# %%` markers are present

### Import Errors

```bash
# Make sure you're in the project root
cd /path/to/phts

# Activate virtual environment
source phts_env/bin/activate

# Install missing packages
pip install <package_name>
```

### Data File Not Found

The workflow requires `graft-loss/data/phts_txpl_ml.sas7bdat`. Make sure:
- The data file is in the correct location
- You have read permissions
- The file is not corrupted

## Reference

- [VS Code Python Interactive Window](https://code.visualstudio.com/docs/python/jupyter-support-py)
- [Calculator Workflow Documentation](../calculator/README.md)
- [SHAP/FFA Workflow](../calculator/README_shap_ffa.md)

---

**Last Updated**: January 26, 2026
