#!/bin/bash

# Push DTVMDotfiles to GitHub
# This script automates the process of committing and pushing to GitHub

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Push DTVMDotfiles to GitHub                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if GitHub username is provided
if [ -z "$1" ]; then
    echo "Usage: ./push_to_github.sh <github_username> [use_ssh]"
    echo ""
    echo "Examples:"
    echo "  ./push_to_github.sh myusername          # Use HTTPS"
    echo "  ./push_to_github.sh myusername ssh      # Use SSH"
    echo ""
    echo "Note: Make sure you have created the repository on GitHub first:"
    echo "  https://github.com/new"
    echo ""
    exit 1
fi

GITHUB_USERNAME="$1"
USE_SSH="${2:-https}"

echo "📋 Configuration:"
echo "  GitHub Username: $GITHUB_USERNAME"
echo "  Authentication: $USE_SSH"
echo ""

# Check git configuration
echo "🔍 Checking Git configuration..."
GIT_NAME=$(git config user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config user.email 2>/dev/null || echo "")

if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    echo "⚠️  Git user info not configured. Please run:"
    echo ""
    echo "  git config user.name \"Your Name\""
    echo "  git config user.email \"your.email@example.com\""
    echo ""
    echo "Or use global config:"
    echo "  git config --global user.name \"Your Name\""
    echo "  git config --global user.email \"your.email@example.com\""
    echo ""
    exit 1
fi

echo "✓ Git configured as: $GIT_NAME <$GIT_EMAIL>"
echo ""

# Change to DTVMDotfiles directory
cd "$SCRIPT_DIR"

echo "📁 Working directory: $(pwd)"
echo ""

# Check if there are any commits
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")

if [ "$COMMIT_COUNT" -eq "0" ]; then
    echo "📝 Creating initial commit..."
    echo ""

    # Stage all files
    git add .

    # Create commit
    git commit -m "Initial commit: Dotfiles sync infrastructure

- Add release.sh: Release dotfiles to external DTVM directory
- Add store.sh: Store external DTVM files to dotfiles folder
- Add RELEASE_STORE_README.md: Complete usage documentation
- Add SYNC_README.md: Synchronization tools guide
- Add UPLOAD_GUIDE.md: GitHub upload instructions
- Add dotfiles/: Configuration files and directories (.claude, .git/info/exclude, qa.md, init.sh, CLAUDE.md)"

    echo "✓ Initial commit created"
else
    echo "ℹ️  Repository already has commits"

    # Check if there are any changes to commit
    if ! git diff-index --quiet HEAD --; then
        echo "📝 Committing changes..."
        git add .
        git commit -m "Update: Modify dotfiles and scripts"
        echo "✓ Changes committed"
    else
        echo "ℹ️  No changes to commit"
    fi
fi

echo ""

# Check if remote is already configured
if git remote get-url origin 2>/dev/null >/dev/null; then
    echo "ℹ️  Remote 'origin' already configured"
    REMOTE_URL=$(git remote get-url origin)
    echo "  URL: $REMOTE_URL"
else
    echo "🔗 Adding remote repository..."

    # Set remote URL based on authentication method
    if [ "$USE_SSH" = "ssh" ]; then
        REMOTE_URL="git@github.com:${GITHUB_USERNAME}/DTVMDotfiles.git"
    else
        REMOTE_URL="https://github.com/${GITHUB_USERNAME}/DTVMDotfiles.git"
    fi

    git remote add origin "$REMOTE_URL"
    echo "✓ Remote added: $REMOTE_URL"
fi

echo ""

# Ensure we're on main branch
echo "🌿 Ensuring main branch..."
git branch -M main
echo "✓ On main branch"

echo ""

# Push to GitHub
echo "🚀 Pushing to GitHub..."
git push -u origin main

echo ""
echo "✅ Success!"
echo ""
echo "Your repository is now available at:"
echo "  https://github.com/${GITHUB_USERNAME}/DTVMDotfiles"
echo ""
echo "You can now:"
echo "  - Visit your repository on GitHub"
echo "  - Clone it on other machines: git clone https://github.com/${GITHUB_USERNAME}/DTVMDotfiles.git"
echo "  - Make changes and push with: git push"
echo ""
