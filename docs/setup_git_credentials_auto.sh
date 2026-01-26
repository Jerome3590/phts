#!/bin/bash
# Setup Git Credentials for GitHub on EC2 (Non-Interactive Version)
# Usage: ./setup_git_credentials_auto.sh <username> <token>
#   OR:   GITHUB_USERNAME=user GITHUB_TOKEN=token ./setup_git_credentials_auto.sh

set -e

echo "=== Git Credentials Setup (Auto) ==="

# Get username from argument or environment variable
if [ -n "$1" ]; then
    GITHUB_USERNAME="$1"
elif [ -z "$GITHUB_USERNAME" ]; then
    echo "Error: GitHub username required."
    echo "Usage: $0 <username> <token>"
    echo "   OR: GITHUB_USERNAME=user GITHUB_TOKEN=token $0"
    exit 1
fi

# Get token from argument or environment variable
if [ -n "$2" ]; then
    GITHUB_TOKEN="$2"
elif [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token required."
    echo "Usage: $0 <username> <token>"
    echo "   OR: GITHUB_USERNAME=user GITHUB_TOKEN=token $0"
    exit 1
fi

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo "Error: Git is not installed. Please install Git first."
    exit 1
fi

# Configure Git credential helper
git config --global credential.helper store

# Create credentials file using sed
CREDENTIALS_FILE="$HOME/.git-credentials"
CREDENTIALS_LINE="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com"

# Create or update credentials file
if [ -f "$CREDENTIALS_FILE" ]; then
    # Remove existing GitHub entry if it exists
    sed -i '/github\.com/d' "$CREDENTIALS_FILE" 2>/dev/null || sed -i '' '/github\.com/d' "$CREDENTIALS_FILE"
fi

# Append new credentials
echo "$CREDENTIALS_LINE" >> "$CREDENTIALS_FILE"

# Set proper permissions
chmod 600 "$CREDENTIALS_FILE"

echo "✓ Git credentials configured successfully!"
echo "✓ Credentials saved to: $CREDENTIALS_FILE"
