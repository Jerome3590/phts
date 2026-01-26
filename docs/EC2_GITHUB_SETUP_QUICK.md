# Quick Setup: GitHub PAT Token on EC2 (No More Prompts)

## One-Time Setup to Stop Password Prompts

### Method 1: Automated Script (Easiest)

```bash
# Download and run the setup script
curl -O https://raw.githubusercontent.com/Jerome3590/phts/main/docs/setup_git_credentials.sh
# OR if already cloned:
chmod +x docs/setup_git_credentials.sh
./docs/setup_git_credentials.sh

# The script will prompt for username and token
```

**Or use the non-interactive version:**
```bash
# With arguments
./docs/setup_git_credentials_auto.sh Jerome3590 YOUR_TOKEN

# Or with environment variables
GITHUB_USERNAME=Jerome3590 GITHUB_TOKEN=YOUR_TOKEN ./docs/setup_git_credentials_auto.sh
```

### Method 2: Manual Setup (Write Credentials Directly with nano)

```bash
# 1. Configure Git to use credential store
git config --global credential.helper store

# 2. Create/edit the credentials file
nano ~/.git-credentials

# 3. Add this line (replace YOUR_TOKEN with your actual PAT):
https://Jerome3590:YOUR_TOKEN@github.com

# 4. Save and exit (Ctrl+X, then Y, then Enter)

# 5. Set proper permissions
chmod 600 ~/.git-credentials
```

**That's it!** Now Git won't ask for credentials.

### Method 2: Let Git Save It Automatically

```bash
# 1. Configure Git to store credentials
git config --global credential.helper store

# 2. Clone/pull once (enter credentials when prompted)
git clone https://github.com/Jerome3590/phts.git

# When prompted:
# Username: Jerome3590
# Password: <paste your PAT token>
```

**Git will automatically save to `~/.git-credentials`**

### Method 3: One-Line Command (Using sed)

```bash
# Configure and write credentials in one go
git config --global credential.helper store && \
echo "https://Jerome3590:YOUR_TOKEN@github.com" > ~/.git-credentials && \
chmod 600 ~/.git-credentials
```

**Replace `YOUR_TOKEN` with your actual PAT token.**

### Step 3: Verify It Works

```bash
# Test without being prompted
cd phts
git pull

# Should work without asking for credentials
```

---

## Alternative: Cache Credentials Temporarily

If you prefer credentials to expire (more secure):

```bash
# Cache for 24 hours
git config --global credential.helper 'cache --timeout=86400'

# Cache for 1 week
git config --global credential.helper 'cache --timeout=604800'
```

---

## Troubleshooting

**Still being prompted?**

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

**Want to remove stored credentials?**

```bash
# Remove the credentials file
rm ~/.git-credentials

# Or clear cache
git credential-cache exit
```

---

## Security Note

The `store` option saves your token in plain text at `~/.git-credentials`. This is fine for EC2 instances where:
- Only you have access
- The instance is properly secured
- You're comfortable with the token being stored

For shared systems, use `cache` with a shorter timeout instead.
