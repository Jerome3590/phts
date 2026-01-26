# Setting Up GitHub on EC2

This guide explains how to configure GitHub access on an EC2 instance.

## Option 1: SSH Keys (Recommended)

### Step 1: Generate SSH Key on EC2

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ec2-user@your-ec2-ip

# Generate a new SSH key pair
ssh-keygen -t ed25519 -C "your-email@example.com"

# Or if ed25519 is not supported, use RSA:
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# Press Enter to accept default location (~/.ssh/id_ed25519 or ~/.ssh/id_rsa)
# Optionally set a passphrase (recommended for security)
```

### Step 2: Add SSH Key to SSH Agent

```bash
# Start the ssh-agent
eval "$(ssh-agent -s)"

# Add your SSH private key to the ssh-agent
ssh-add ~/.ssh/id_ed25519
# Or if using RSA:
ssh-add ~/.ssh/id_rsa
```

### Step 3: Copy Public Key to GitHub

```bash
# Display your public key
cat ~/.ssh/id_ed25519.pub
# Or if using RSA:
cat ~/.ssh/id_rsa.pub
```

**Then on GitHub:**
1. Go to GitHub.com → Settings → SSH and GPG keys
2. Click "New SSH key"
3. Give it a title (e.g., "EC2 Instance")
4. Paste the public key content
5. Click "Add SSH key"

### Step 4: Test SSH Connection

```bash
# Test GitHub SSH connection
ssh -T git@github.com

# You should see: "Hi username! You've successfully authenticated..."
```

### Step 5: Clone Repository Using SSH

```bash
# Clone using SSH URL (found on GitHub repo page, green "Code" button)
git clone git@github.com:Jerome3590/phts.git

# Or if already cloned with HTTPS, change remote:
cd phts
git remote set-url origin git@github.com:Jerome3590/phts.git
```

---

## Option 2: HTTPS with Personal Access Token

### Step 1: Generate Personal Access Token on GitHub

1. Go to GitHub.com → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a name (e.g., "EC2 Access")
4. Select scopes:
   - ✅ `repo` (full control of private repositories)
   - ✅ `workflow` (if using GitHub Actions)
5. Click "Generate token"
6. **Copy the token immediately** (you won't see it again!)

### Step 2: Configure Git on EC2

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ec2-user@your-ec2-ip

# Configure Git (one-time setup)
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"

# Clone repository (will prompt for username and token)
git clone https://github.com/Jerome3590/phts.git

# When prompted:
# Username: Jerome3590
# Password: <paste your personal access token>
```

### Step 3: Configure Credential Storage (Recommended)

**Option A: Store Credentials Permanently (Easiest)**

**Method 1: Manual Setup (Write Directly to File)**

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

**Option B: Cache Credentials Temporarily (More Secure)**

```bash
# Cache credentials for 8 hours (28800 seconds)
git config --global credential.helper 'cache --timeout=28800'

# Or cache for 24 hours
git config --global credential.helper 'cache --timeout=86400'

# After timeout, you'll need to enter credentials again
```

**Option C: Use Credential Helper with File Storage (Recommended for EC2)**

```bash
# Store credentials in a file (works across reboots)
git config --global credential.helper store

# Or use a custom location
git config --global credential.helper 'store --file ~/.git-credentials'

# First time: enter credentials when prompted
git clone https://github.com/Jerome3590/phts.git
# After that, credentials are saved automatically
```

**Option D: Embed Token in Remote URL (Less Secure, But Convenient)**

```bash
# Clone with token embedded in URL (one-time setup)
git clone https://Jerome3590:YOUR_TOKEN@github.com/Jerome3590/phts.git

# Or update existing remote
git remote set-url origin https://Jerome3590:YOUR_TOKEN@github.com/Jerome3590/phts.git

# ⚠️ WARNING: Token will be visible in git config and command history
# Only use this if you're the only one with access to the EC2 instance
```

**Recommended for EC2: Use Option C (store helper)**

---

## Quick Setup Script for EC2

Save this as `setup_github.sh` and run it on your EC2 instance:

```bash
#!/bin/bash
# GitHub Setup Script for EC2

set -e

echo "=== GitHub Setup for EC2 ==="

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo "Installing Git..."
    if command -v yum &> /dev/null; then
        sudo yum update -y
        sudo yum install git -y
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install git -y
    fi
fi

# Configure Git
read -p "Enter your Git username: " GIT_USERNAME
read -p "Enter your Git email: " GIT_EMAIL

git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"

# Choose authentication method
echo ""
echo "Choose authentication method:"
echo "1) SSH Keys (Recommended)"
echo "2) HTTPS with Personal Access Token"
read -p "Enter choice (1 or 2): " AUTH_CHOICE

if [ "$AUTH_CHOICE" == "1" ]; then
    # SSH Key setup
    echo ""
    echo "=== Setting up SSH Keys ==="
    
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        read -p "Enter your email for SSH key: " SSH_EMAIL
        ssh-keygen -t ed25519 -C "$SSH_EMAIL" -f ~/.ssh/id_ed25519 -N ""
    fi
    
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519
    
    echo ""
    echo "=== Your Public SSH Key ==="
    cat ~/.ssh/id_ed25519.pub
    echo ""
    echo "=== Next Steps ==="
    echo "1. Copy the public key above"
    echo "2. Go to: https://github.com/settings/keys"
    echo "3. Click 'New SSH key' and paste the key"
    echo "4. Then run: git clone git@github.com:Jerome3590/phts.git"
    
elif [ "$AUTH_CHOICE" == "2" ]; then
    # HTTPS setup
    echo ""
    echo "=== Setting up HTTPS ==="
    echo "1. Go to: https://github.com/settings/tokens"
    echo "2. Generate a new token (classic) with 'repo' scope"
    echo "3. Copy the token"
    echo ""
    read -p "Press Enter after you have your token..."
    
    # Configure credential helper
    git config --global credential.helper 'cache --timeout=3600'
    
    echo ""
    echo "Now clone your repository:"
    echo "git clone https://github.com/Jerome3590/phts.git"
    echo "When prompted, use your GitHub username and the token as password"
fi

echo ""
echo "=== Setup Complete ==="
```

**To use the script:**
```bash
# Make it executable
chmod +x setup_github.sh

# Run it
./setup_github.sh
```

---

## Verify Setup

```bash
# Test Git is working
git --version

# Test GitHub connection (SSH)
ssh -T git@github.com

# Or test HTTPS connection
git ls-remote https://github.com/Jerome3590/phts.git
```

---

## Troubleshooting

### SSH Key Issues

```bash
# Check if SSH key is loaded
ssh-add -l

# If empty, add it again
ssh-add ~/.ssh/id_ed25519

# Test connection with verbose output
ssh -vT git@github.com
```

### Permission Issues

```bash
# Fix SSH directory permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

### HTTPS Token Issues

```bash
# Clear cached credentials
git credential-cache exit

# Or remove stored credentials
rm ~/.git-credentials

# Check current credential helper
git config --global credential.helper

# Reconfigure if needed
git config --global credential.helper store

# Try cloning again
git clone https://github.com/Jerome3590/phts.git
```

### Verify Credential Storage

```bash
# Check if credentials are stored
cat ~/.git-credentials

# Check Git credential configuration
git config --global --get credential.helper

# Test that credentials work without prompting
git ls-remote https://github.com/Jerome3590/phts.git
```

---

## Security Best Practices

1. **Use SSH keys** instead of HTTPS tokens when possible
2. **Set a passphrase** on your SSH key
3. **Use token expiration** for personal access tokens
4. **Limit token scopes** to only what's needed
5. **Rotate tokens/keys** periodically
6. **Never commit credentials** to the repository

---

## Quick Reference

**SSH URL:**
```bash
git@github.com:Jerome3590/phts.git
```

**HTTPS URL:**
```bash
https://github.com/Jerome3590/phts.git
```

**Change remote URL:**
```bash
# To SSH
git remote set-url origin git@github.com:Jerome3590/phts.git

# To HTTPS
git remote set-url origin https://github.com/Jerome3590/phts.git
```

---

**Last Updated**: January 26, 2026
