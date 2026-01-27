#!/bin/bash
# Clone Repository and Setup Environment for EC2
# This script clones the PHTS repository and sets up the Python environment

set -e

echo "=== PHTS Repository Setup ==="
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

# Clone repository
if [ -d "$REPO_DIR" ]; then
    echo "Repository already exists at $REPO_DIR"
    echo "Pulling latest changes..."
    cd "$REPO_DIR"
    git pull
    cd ..
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$REPO_DIR"
    echo "✓ Repository cloned successfully"
fi

# Navigate to repository
cd "$REPO_DIR"

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

# Check if virtual environment exists
if [ ! -d "$PYTHON_ENV" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$PYTHON_ENV"
    echo "✓ Virtual environment created"
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
    pip install numpy pandas scikit-learn catboost xgboost shap jupyter
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
echo "To run the interactive workflow:"
echo "  python docs/calculator_workflow_interactive.py"
echo ""
