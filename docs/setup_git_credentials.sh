#!/bin/bash
# Setup Git Credentials for GitHub on EC2
# This script configures Git to store credentials permanently

set -e

echo "=== Git Credentials Setup for GitHub ==="

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo "Error: Git is not installed. Please install Git first."
    exit 1
fi

# Get GitHub username
if [ -z "$GITHUB_USERNAME" ]; then
    read -p "Enter your GitHub username: " GITHUB_USERNAME
fi

# Get Personal Access Token
if [ -z "$GITHUB_TOKEN" ]; then
    read -sp "Enter your GitHub Personal Access Token: " GITHUB_TOKEN
    echo ""  # New line after hidden input
fi

# Validate inputs
if [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Username and token are required."
    exit 1
fi

# Configure Git credential helper
echo "Configuring Git credential helper..."
git config --global credential.helper store

# Create credentials file using sed
CREDENTIALS_FILE="$HOME/.git-credentials"
CREDENTIALS_LINE="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com"

# Check if credentials file already exists
if [ -f "$CREDENTIALS_FILE" ]; then
    # Remove existing GitHub entry if it exists
    sed -i '/github\.com/d' "$CREDENTIALS_FILE"
    echo "Removed existing GitHub credentials"
fi

# Append new credentials
echo "$CREDENTIALS_LINE" >> "$CREDENTIALS_FILE"

# Set proper permissions (read/write for owner only)
chmod 600 "$CREDENTIALS_FILE"

echo ""
echo "✓ Git credentials configured successfully!"
echo "✓ Credentials saved to: $CREDENTIALS_FILE"
echo ""
echo "Testing connection..."

# Test the connection
if git ls-remote https://github.com/${GITHUB_USERNAME}/phts.git &>/dev/null; then
    echo "✓ Connection test successful!"
else
    echo "⚠ Warning: Connection test failed. Please verify your token has 'repo' scope."
    echo "  You can test manually with: git ls-remote https://github.com/${GITHUB_USERNAME}/phts.git"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now clone/pull/push without entering credentials:"
echo "  git clone https://github.com/${GITHUB_USERNAME}/phts.git"
