#!/bin/bash

# Setup from DTVMDotfiles
# This script clones DTVMDotfiles, releases files, and runs init.sh
# Usage: ./setup_from_dotfiles.sh [optional-target-directory]

set -e

# Configuration
GITHUB_REPO="https://github.com/abmcar/DTVMDotfiles.git"
TEMP_DIR="${1:-.}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        Setup from DTVMDotfiles                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Clone DTVMDotfiles
echo "📥 Cloning DTVMDotfiles repository..."
echo "   Repository: $GITHUB_REPO"
echo "   Target: $TEMP_DIR"
echo ""

if [ -d "$TEMP_DIR/DTVMDotfiles" ]; then
    echo "⚠️  DTVMDotfiles already exists at $TEMP_DIR/DTVMDotfiles"
    echo "   Updating existing repository..."
    cd "$TEMP_DIR/DTVMDotfiles"
    git pull
else
    cd "$TEMP_DIR"
    git clone "$GITHUB_REPO"
    cd DTVMDotfiles
fi

echo "✅ Repository ready"
echo ""

# Step 2: Run release.sh
echo "🔓 Running release.sh to release files..."
echo ""

if [ ! -f "./release.sh" ]; then
    echo "❌ Error: release.sh not found"
    exit 1
fi

bash ./release.sh

echo ""
echo "✅ Files released successfully"
echo ""

# Step 3: Run init.sh
echo "🚀 Running init.sh from released files..."
echo ""

INIT_SCRIPT="../init.sh"

if [ ! -f "$INIT_SCRIPT" ]; then
    echo "❌ Error: init.sh not found at $INIT_SCRIPT"
    echo "   Available files:"
    ls -la ../
    exit 1
fi

echo "Executing: $INIT_SCRIPT"
echo ""

bash "$INIT_SCRIPT"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  ✅ Setup Complete!                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  ✓ Cloned DTVMDotfiles from GitHub"
echo "  ✓ Released configuration files"
echo "  ✓ Executed init.sh"
echo ""
echo "DTVMDotfiles location: $(pwd)"
echo ""
