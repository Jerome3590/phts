#!/bin/bash
# Clone Repository and Setup Environment for EC2 (Full Clone)
# This script clones the PHTS repository with full git history

set -e

echo "=== PHTS Repository Setup (Full Clone) ==="
echo ""

# Configuration
REPO_URL="https://github.com/Jerome3590/phts.git"
REPO_DIR="phts"
PYTHON_ENV="phts_env"

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo "Installing Git..."
    if command -v yum &> /dev/null; then
        sudo yum update -y
        sudo yum install git -y
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install git -y
    else
        echo "Error: Cannot install Git. Please install manually."
        exit 1
    fi
fi

# Check if we're already in the repository
if [ -d ".git" ] || [ -f "README.md" ]; then
    echo "Already in repository directory"
    REPO_DIR="."
    # If we're in the repo, check if we should pull updates
    if [ -d ".git" ]; then
        echo "Checking for updates..."
        git pull || echo "Note: Could not pull updates (may need credentials setup)"
    fi
elif [ -d "$REPO_DIR" ]; then
    echo "Repository already exists at $REPO_DIR"
    echo "Pulling latest changes..."
    cd "$REPO_DIR"
    git pull || echo "Note: Could not pull updates (may need credentials setup)"
    cd ..
else
    echo "Cloning repository (full history)..."
    git clone "$REPO_URL" "$REPO_DIR"
    echo "✓ Repository cloned successfully"
fi

# Navigate to repository (if not already there)
if [ "$REPO_DIR" != "." ]; then
    cd "$REPO_DIR"
fi

# Check Python installation
if ! command -v python3 &> /dev/null; then
    echo "Installing Python 3..."
    if command -v yum &> /dev/null; then
        sudo yum install python3 python3-pip -y
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install python3 python3-pip -y
    else
        echo "Error: Cannot install Python. Please install manually."
        exit 1
    fi
fi

# Check for existing virtual environments
EXISTING_VENV=""
if [ -d "jupyter-env" ]; then
    EXISTING_VENV="jupyter-env"
    echo "Found existing virtual environment: jupyter-env"
elif [ -d "phts_env" ]; then
    EXISTING_VENV="phts_env"
    echo "Found existing virtual environment: phts_env"
elif [ -d "$PYTHON_ENV" ]; then
    EXISTING_VENV="$PYTHON_ENV"
    echo "Found existing virtual environment: $PYTHON_ENV"
fi

# Use existing venv or create new one
if [ -n "$EXISTING_VENV" ]; then
    PYTHON_ENV="$EXISTING_VENV"
    echo "Using existing virtual environment: $PYTHON_ENV"
else
    if [ ! -d "$PYTHON_ENV" ]; then
        echo "Creating Python virtual environment..."
        python3 -m venv "$PYTHON_ENV"
        echo "✓ Virtual environment created: $PYTHON_ENV"
    fi
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$PYTHON_ENV/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install requirements (if requirements.txt exists)
if [ -f "requirements.txt" ]; then
    echo "Installing requirements from requirements.txt..."
    pip install -r requirements.txt
elif [ -f "graft-loss/cohort_analysis/calculator/requirements.txt" ]; then
    echo "Installing calculator requirements..."
    pip install -r graft-loss/cohort_analysis/calculator/requirements.txt
else
    echo "Installing common dependencies..."
    pip install numpy pandas scikit-learn catboost xgboost shap jupyter notebook matplotlib
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Repository location: $(pwd)"
echo "Virtual environment: $PYTHON_ENV"
echo ""
echo "To activate the environment in the future:"
echo "  cd $REPO_DIR"
echo "  source $PYTHON_ENV/bin/activate"
echo ""
echo "To start Jupyter notebook:"
echo "  jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser"
echo ""
echo "Then create SSH tunnel from local machine:"
echo "  ssh -i your-key.pem -L 8888:localhost:8888 ec2-user@your-ec2-ip"
echo ""
echo "Open notebook:"
echo "  graft-loss/cohort_analysis/calculator/calculator_workflow.ipynb"
echo ""
