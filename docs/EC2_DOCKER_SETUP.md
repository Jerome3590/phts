# Docker Installation on EC2

This guide explains how to install Docker on EC2 instances for building and pushing Lambda container images.

## Quick Installation

### Amazon Linux 2

```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install docker -y

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add ec2-user to docker group (so you can run docker without sudo)
sudo usermod -a -G docker ec2-user

# Log out and back in for group changes to take effect
# Or run: newgrp docker

# Verify installation
docker --version
docker ps
```

### Amazon Linux 2023

```bash
# Update system
sudo dnf update -y

# Install Docker
sudo dnf install docker -y

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add ec2-user to docker group
sudo usermod -a -G docker ec2-user

# Log out and back in, or run: newgrp docker

# Verify installation
docker --version
docker ps
```

### Ubuntu

```bash
# Update system
sudo apt-get update

# Install Docker
sudo apt-get install docker.io -y

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add ubuntu user to docker group
sudo usermod -aG docker ubuntu

# Log out and back in, or run: newgrp docker

# Verify installation
docker --version
docker ps
```

---

## Detailed Setup

### Step 1: Identify Your EC2 OS

```bash
# Check OS version
cat /etc/os-release

# Or check which package manager you have
which yum    # Amazon Linux 2
which dnf    # Amazon Linux 2023
which apt-get # Ubuntu/Debian
```

### Step 2: Install Docker

Follow the appropriate installation method above based on your OS.

### Step 3: Configure Docker (Optional)

```bash
# Configure Docker to start on boot (already done with systemctl enable)
sudo systemctl enable docker

# Check Docker status
sudo systemctl status docker

# View Docker logs if needed
sudo journalctl -u docker
```

### Step 4: Test Docker

```bash
# Test Docker with hello-world
docker run hello-world

# If you get permission denied, you may need to:
# 1. Log out and back in (for group changes)
# 2. Or use: newgrp docker
# 3. Or run with sudo: sudo docker run hello-world
```

---

## Docker for AWS ECR

To push images to AWS ECR, you need AWS CLI installed. **If your EC2 instance has an IAM role attached, credentials are automatically provided** - no need to run `aws configure`.

```bash
# Install AWS CLI (if not already installed)
# Amazon Linux 2
sudo yum install aws-cli -y

# Amazon Linux 2023
sudo dnf install awscli -y

# Ubuntu
sudo apt-get install awscli -y

# Test AWS CLI (uses EC2 instance role credentials automatically)
aws sts get-caller-identity

# If this works, you're all set! No need to run aws configure.
# If it fails, you may need to:
# 1. Attach an IAM role to your EC2 instance with ECR permissions, OR
# 2. Run: aws configure (and enter credentials manually)
```

### Login to ECR

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-east-1

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

---

## Troubleshooting

### Permission Denied

**Problem:** `permission denied while trying to connect to the Docker daemon socket`

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or:
newgrp docker

# Verify
docker ps
```

### Docker Service Not Running

**Problem:** `Cannot connect to the Docker daemon`

**Solution:**
```bash
# Start Docker service
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker

# Check status
sudo systemctl status docker
```

### ECR Login Issues

**Problem:** `Error: Unable to locate credentials`

**Solution:**

**Option 1: Use EC2 Instance Role (Recommended)**
```bash
# Attach an IAM role to your EC2 instance with these permissions:
# - AmazonEC2ContainerRegistryFullAccess (or custom policy with ECR push/pull)
# 
# The instance will automatically use these credentials - no aws configure needed
# Verify it's working:
aws sts get-caller-identity
```

**Option 2: Manual Credentials**
```bash
# Configure AWS credentials manually
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
export AWS_DEFAULT_REGION=us-east-1
```

### Docker Build Fails

**Problem:** Build errors or out of memory

**Solution:**
```bash
# Check available disk space
df -h

# Check available memory
free -h

# Clean up Docker
docker system prune -a

# Use larger EC2 instance if needed (e.g., t3.large or larger)
```

---

## Verification Checklist

After installation, verify:

- [ ] Docker is installed: `docker --version`
- [ ] Docker service is running: `sudo systemctl status docker`
- [ ] Can run containers: `docker run hello-world`
- [ ] User in docker group: `groups | grep docker`
- [ ] AWS CLI configured: `aws sts get-caller-identity`
- [ ] Can login to ECR: `aws ecr get-login-password --region us-east-1`

---

## Using Docker for Lambda Deployment

Once Docker is installed, you can build and push Lambda container images:

```bash
cd graft-loss/cohort_analysis/calculator/risk_dashboard

# Build and push Docker image
./docker_build_phts.sh

# This will:
# 1. Prepare lambda directory
# 2. Build Docker image
# 3. Push to ECR
# 4. Output ECR URI for Lambda update
```

---

## Quick Reference

**Install Docker (Amazon Linux 2):**
```bash
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user
newgrp docker
```

**Install Docker (Ubuntu):**
```bash
sudo apt-get install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ubuntu
newgrp docker
```

**Test Docker:**
```bash
docker --version
docker run hello-world
```

**Login to ECR:**
```bash
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin \
    $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
```

---

**Last Updated**: January 26, 2026
