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
# Docker is a prerequisite. This script installs Docker Engine + the Compose
# plugin automatically if Docker is not already present, and skips that step if
# it already is. Disable the behaviour with INSTALL_DOCKER=0.
#
# Usage:
#   ./setup-launcher.sh            # install / upgrade to the LATEST release
#   ./setup-launcher.sh v2.1.0     # install a specific release tag
#   INSTALL_DOCKER=0 ./setup-launcher.sh   # skip the Docker prerequisite step
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- Configuration (point this at YOUR public distribution repo) ------------
DIST_REPO="zeblok/launcher-dist"   # PUBLIC repo that hosts the .deb release assets
ASSET_REGEX='_amd64\.deb'          # which asset to pick from a release
PKG_NAME="zbl-launcher"            # dpkg package name (used for the version check)
REQ_VERSION="${1:-}"               # optional release tag; empty = latest release
INSTALL_DOCKER="${INSTALL_DOCKER:-1}"  # 1 = auto-install Docker if missing, 0 = skip
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

# Ensure Docker Engine + the Compose plugin are installed. Idempotent: if Docker
# is already present this does nothing. Disable entirely with INSTALL_DOCKER=0.
ensure_docker() {
  [ "$INSTALL_DOCKER" = "1" ] || { log "INSTALL_DOCKER=0 - skipping the Docker prerequisite."; return; }

  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed ($(docker --version 2>/dev/null)) - skipping."
    return
  fi

  log "Docker not found - installing Docker Engine + Compose plugin ..."

  # Read distro info from /etc/os-release. Declare the fields we read as LOCAL
  # FIRST, so that file's own VERSION=... line cannot clobber this script's
  # variables (it defines VERSION, which would otherwise break the release lookup).
  local ID="" ID_LIKE="" VERSION_CODENAME="" UBUNTU_CODENAME=""
  # shellcheck disable=SC1091
  . /etc/os-release
  local docker_distro codename
  case "${ID:-ubuntu}" in
    ubuntu) docker_distro="ubuntu"; codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" ;;
    debian) docker_distro="debian"; codename="${VERSION_CODENAME:-}" ;;
    *)
      if printf '%s' "${ID_LIKE:-}" | grep -q debian && ! printf '%s' "${ID_LIKE:-}" | grep -q ubuntu; then
        docker_distro="debian"; codename="${VERSION_CODENAME:-}"
      else
        docker_distro="ubuntu"; codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
      fi ;;
  esac
  [ -n "$codename" ] || die "Could not determine the distro codename for the Docker apt repo."

  # prerequisites + Docker's GPG key
  $SUDO apt-get update
  $SUDO apt-get install -y ca-certificates curl
  $SUDO install -m 0755 -d /etc/apt/keyrings
  $SUDO curl -fsSL "https://download.docker.com/linux/$docker_distro/gpg" -o /etc/apt/keyrings/docker.asc
  $SUDO chmod a+r /etc/apt/keyrings/docker.asc

  # add the repo (architecture + codename auto-detected)
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$docker_distro $codename stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

  # install engine + CLI + containerd + buildx + compose plugin
  $SUDO apt-get update
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # enable + start the service now and on boot (skipped if there is no systemd)
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl enable --now docker || warn "Could not enable/start the docker service automatically."
  fi

  # optional convenience: let the invoking non-root user run docker without sudo
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    $SUDO usermod -aG docker "$SUDO_USER" || true
    log "Added '$SUDO_USER' to the 'docker' group (log out and back in for it to take effect)."
  fi

  log "Docker installed: $(docker --version 2>/dev/null)."
}

# Resolve the download URL of the .deb asset for the chosen release using the
# PUBLIC GitHub API. A public repo needs no authentication to read releases.
resolve_deb_url() {
  local api
  if [ -n "$REQ_VERSION" ]; then
    api="https://api.github.com/repos/$DIST_REPO/releases/tags/$REQ_VERSION"
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
  ensure_docker          # install Docker first if it's missing (prerequisite)

  log "Looking up the ${REQ_VERSION:-latest} release of $DIST_REPO ..."
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
    warn "apt install failed - falling back to dpkg and fixing dependencies ..."
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
