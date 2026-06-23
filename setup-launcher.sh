#!/usr/bin/env bash
#
# setup-launcher.sh  —  customer install script for zbl-launcher
# -----------------------------------------------------------------------------
# Downloads the latest zbl-launcher .deb from the PUBLIC distribution repo and
# installs it on Debian/Ubuntu (amd64), then deletes the downloaded .deb.
#
# No GitHub login, token, or key is required. The distribution repo is public,
# while your application SOURCE CODE stays private in a separate repo. This file
# is safe to hand to customers and to commit anywhere.
#
# Usage:
#   ./setup-launcher.sh            # install / upgrade to the LATEST release
#   ./setup-launcher.sh v2.1.0     # install a specific release tag
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- Configuration (point this at YOUR public distribution repo) ------------
DIST_REPO="zeblok/launcher-dist"   # PUBLIC repo that hosts the .deb release assets
ASSET_REGEX='_amd64\.deb'          # which asset to pick from a release
PKG_NAME="zbl-launcher"            # dpkg package name (used for the version check)
VERSION="${1:-}"                   # optional release tag; empty = latest release
# -----------------------------------------------------------------------------

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

setup_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "Root privileges required (install 'sudo' or run this script as root)."
  fi
}

# Resolve the download URL of the .deb asset for the chosen release using the
# PUBLIC GitHub API. A public repo needs no authentication to read releases.
resolve_deb_url() {
  local api
  if [ -n "$VERSION" ]; then
    api="https://api.github.com/repos/$DIST_REPO/releases/tags/$VERSION"
  else
    api="https://api.github.com/repos/$DIST_REPO/releases/latest"
  fi
  curl -fsSL -H "Accept: application/vnd.github+json" "$api" \
    | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+'"$ASSET_REGEX"'"' \
    | sed -E 's/.*"(https[^"]+)".*/\1/' \
    | head -n1
}

main() {
  command -v curl >/dev/null 2>&1 || die "'curl' is required but not installed."
  setup_sudo

  log "Looking up the ${VERSION:-latest} release of $DIST_REPO ..."
  local url
  url="$(resolve_deb_url)" || true
  [ -n "$url" ] || die "Could not find a *${ASSET_REGEX} asset in that release (check DIST_REPO / VERSION)."

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  local deb
  deb="$TMPDIR/$(basename "$url")"

  log "Downloading $(basename "$url") ..."
  curl -fL --retry 3 -o "$deb" "$url"

  log "Installing (apt resolves any dependencies automatically) ..."
  if ! $SUDO apt-get install -y "$deb"; then
    warn "apt install failed — falling back to dpkg and fixing dependencies ..."
    $SUDO dpkg -i "$deb" || true
    $SUDO apt-get install -f -y
  fi

  if command -v dpkg-query >/dev/null 2>&1 \
      && dpkg-query -W -f='${Version}' "$PKG_NAME" >/dev/null 2>&1; then
    log "Installed $PKG_NAME version: $(dpkg-query -W -f='${Version}' "$PKG_NAME")"
  fi

  # As requested: remove the .deb after a successful install.
  rm -f "$deb"
  log "Cleaned up the downloaded .deb. Launcher setup complete."
}

main "$@"
