#!/bin/bash
# Quick script to activate the correct virtual environment
# Usage: source activate_venv.sh

# Check for existing virtual environments in order of preference
if [ -d "jupyter-env" ]; then
    echo "Activating jupyter-env..."
    source jupyter-env/bin/activate
elif [ -d "phts_env" ]; then
    echo "Activating phts_env..."
    source phts_env/bin/activate
else
    echo "Error: No virtual environment found."
    echo "Available options:"
    echo "  - jupyter-env"
    echo "  - phts_env"
    echo ""
    echo "Run clone_and_setup.sh to create a virtual environment."
    return 1 2>/dev/null || exit 1
fi

echo "✓ Virtual environment activated: $(basename $VIRTUAL_ENV)"
echo "Python: $(which python)"
echo "Pip: $(which pip)"
