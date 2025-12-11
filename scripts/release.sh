#!/usr/bin/env bash
# ============================================================================
# release.sh - Publish bgs to Homebrew tap
# 
# Usage: ./scripts/release.sh [version]
#   version: optional, defaults to version in common.sh (e.g., 1.0.0)
#
# This script will:
# 1. Create git tag and push to bg-cmd repo
# 2. Download release tarball and calculate SHA256
# 3. Generate Formula file
# 4. Push Formula to homebrew-tap repo
# ============================================================================

set -e

# Config
REPO_OWNER="oreoft"
REPO_NAME="bg-cmd"
TAP_REPO="homebrew-tap"
FORMULA_NAME="bgs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Get version from argument or common.sh
if [[ -n "$1" ]]; then
    VERSION="$1"
else
    VERSION=$(grep 'BG_VERSION=' "$PROJECT_DIR/libexec/lib/common.sh" | cut -d'"' -f2)
fi

if [[ -z "$VERSION" ]]; then
    log_error "Cannot determine version"
    exit 1
fi

log_info "Releasing version: $VERSION"

# ============================================================================
# Step 1: Create and push tag
# ============================================================================
log_info "Step 1: Creating git tag v${VERSION}..."

cd "$PROJECT_DIR"

# Check if tag exists
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    log_warn "Tag v${VERSION} already exists, skipping tag creation"
else
    # Make sure all changes are committed
    if [[ -n $(git status --porcelain) ]]; then
        log_error "There are uncommitted changes. Please commit first."
        exit 1
    fi
    
    git tag -a "v${VERSION}" -m "Release v${VERSION}"
    log_info "Tag created: v${VERSION}"
fi

# Push tag
log_info "Pushing tag to remote..."
git push origin "v${VERSION}" 2>/dev/null || log_warn "Tag already pushed or push failed"

# Push code
git push origin master 2>/dev/null || git push origin main 2>/dev/null || true

# ============================================================================
# Step 2: Calculate SHA256
# ============================================================================
log_info "Step 2: Calculating SHA256..."

TARBALL_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/tags/v${VERSION}.tar.gz"

# Wait a bit for GitHub to generate the tarball
log_info "Waiting for GitHub to generate tarball..."
sleep 3

# Download and calculate SHA256
SHA256=$(curl -sL "$TARBALL_URL" | shasum -a 256 | cut -d' ' -f1)

if [[ -z "$SHA256" || "$SHA256" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
    log_error "Failed to calculate SHA256. The release may not exist yet."
    log_error "Please create a release on GitHub first: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/new"
    exit 1
fi

log_info "SHA256: $SHA256"

# ============================================================================
# Step 3: Generate Formula
# ============================================================================
log_info "Step 3: Generating Formula..."

FORMULA_CONTENT=$(cat << EOF
# Homebrew Formula for bgs
# bgs = bilibili goods

class Bgs < Formula
  desc "Bilibili Goods CLI - batch publish/buy items on Bilibili Mall"
  homepage "https://github.com/${REPO_OWNER}/${REPO_NAME}"
  url "${TARBALL_URL}"
  sha256 "${SHA256}"
  license "MIT"
  version "${VERSION}"

  depends_on "jq"
  depends_on "qrencode"

  def install
    bin.install "bin/bgs"
    libexec.install Dir["libexec/*"]
    
    # Update libexec path in main script
    inreplace bin/"bgs",
      'LIBEXEC_DIR="\${SCRIPT_DIR}/../libexec"',
      "LIBEXEC_DIR=\"#{libexec}\""
  end

  def caveats
    <<~EOS
      bgs (bilibili goods) has been installed!

      Quick start:
        1. Login: bgs auth login
        2. Set price: bgs config publish.price 200
        3. Publish: bgs publish
        4. Buy: bgs buy

      For help: bgs help
    EOS
  end

  test do
    assert_match "bgs version", shell_output("#{bin}/bgs version")
  end
end
EOF
)

# ============================================================================
# Step 4: Push to homebrew-tap
# ============================================================================
log_info "Step 4: Pushing to homebrew-tap..."

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone tap repo
log_info "Cloning homebrew-tap..."
git clone "https://github.com/${REPO_OWNER}/${TAP_REPO}.git" tap
cd tap

# Create Formula directory if not exists
mkdir -p Formula

# Write Formula
echo "$FORMULA_CONTENT" > "Formula/${FORMULA_NAME}.rb"

# Commit and push
git add .
if git diff --staged --quiet; then
    log_warn "No changes to commit"
else
    git commit -m "Update ${FORMULA_NAME} to v${VERSION}"
    git push origin main 2>/dev/null || git push origin master
    log_info "Formula pushed to homebrew-tap"
fi

# Cleanup
cd /
rm -rf "$TEMP_DIR"

# ============================================================================
# Done
# ============================================================================
echo ""
log_info "=========================================="
log_info "Release v${VERSION} completed!"
log_info "=========================================="
echo ""
echo "Users can now install with:"
echo ""
echo "  brew tap ${REPO_OWNER}/tap"
echo "  brew install ${FORMULA_NAME}"
echo ""
echo "Or update with:"
echo ""
echo "  brew update"
echo "  brew upgrade ${FORMULA_NAME}"
echo ""

