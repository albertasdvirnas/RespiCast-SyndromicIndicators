#!/usr/bin/env bash
#
# Install R and the GP-EDM stack (GPEDM + laGP) used by the IceLab-EDM model.
#
# Idempotent: re-running it is cheap once everything is installed.
# Portable: works on a Debian/Ubuntu box with apt, and degrades to plain
# install.packages() elsewhere.
#
# Environment overrides:
#   GPEDM_SRC_DIR  where package sources are cloned (default: $TMPDIR/gpedm-src)
#   GPEDM_REPO     GPEDM git remote
#   LAGP_REPO      laGP git remote (the read-only CRAN mirror on GitHub)

set -euo pipefail

SRC_DIR="${GPEDM_SRC_DIR:-${TMPDIR:-/tmp}/gpedm-src}"
GPEDM_REPO="${GPEDM_REPO:-https://github.com/tanyalrogers/GPEDM}"
LAGP_REPO="${LAGP_REPO:-https://github.com/cran/laGP}"

log() { printf '[setup-gpedm] %s\n' "$*"; }
die() { printf '[setup-gpedm] ERROR: %s\n' "$*" >&2; exit 1; }

apt_usable() { command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; }

apt_update_once() {
  if [ -z "${_APT_UPDATED:-}" ]; then
    # The image may carry PPAs that egress policy blocks; a failed index for
    # one of those must not abort the run, the Ubuntu archive is what we need.
    DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
    _APT_UPDATED=1
  fi
}

apt_install() {
  apt_update_once
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
}

# Is an R package importable?
r_has() {
  Rscript -e "quit(status = as.integer(!requireNamespace('$1', quietly = TRUE)))" >/dev/null 2>&1
}

# ---------------------------------------------------------------- R itself --
if ! command -v Rscript >/dev/null 2>&1; then
  apt_usable || die "Rscript not found and apt-get is unavailable; install R >= 4.0 first"
  log "installing R (r-base-dev)"
  apt_install r-base-dev
fi
log "using $(Rscript -e 'cat(R.version.string)')"

# --------------------------------------------------------- library location --
R_LIB="$(Rscript -e 'cat(.libPaths()[1])')"
if [ ! -w "$R_LIB" ]; then
  R_LIB="${R_LIBS_USER:-$HOME/R/library}"
  mkdir -p "$R_LIB"
  export R_LIBS_USER="$R_LIB"
  log "site library not writable, installing into $R_LIB"
fi

# ------------------------------------------------------------- CRAN deps ----
# Prefer distro packages: this environment's egress policy blocks CRAN, and apt
# packages are prebuilt anyway. Fall back to CRAN where apt is not an option.
#   Rcpp, Matrix -> GPEDM;  tgp -> laGP
install_dep() {
  local pkg="$1" aptpkg="$2"
  if r_has "$pkg"; then
    log "$pkg already installed"
    return
  fi
  if apt_usable && apt-cache show "$aptpkg" >/dev/null 2>&1; then
    log "installing $pkg via apt ($aptpkg)"
    apt_install "$aptpkg"
  else
    log "installing $pkg from CRAN"
    Rscript -e "install.packages('$pkg', repos = 'https://cloud.r-project.org', lib = '$R_LIB')"
  fi
  r_has "$pkg" || die "failed to install $pkg"
}

install_dep Rcpp   r-cran-rcpp
install_dep Matrix r-cran-matrix
install_dep tgp    r-cran-tgp

# --------------------------------------------------- source-built packages --
# laGP and GPEDM are not in the Ubuntu archive. Build them from git: this works
# whether or not CRAN is reachable, and GPEDM is GitHub-only in any case.
install_from_git() {
  local pkg="$1" repo="$2"
  local dir="$SRC_DIR/$pkg"
  if r_has "$pkg"; then
    log "$pkg already installed"
    return
  fi
  mkdir -p "$SRC_DIR"
  if [ -d "$dir/.git" ]; then
    log "refreshing $pkg source in $dir"
    git -C "$dir" fetch --depth 1 origin HEAD >/dev/null 2>&1 || true
    git -C "$dir" reset --hard FETCH_HEAD >/dev/null 2>&1 || true
  else
    log "cloning $pkg from $repo"
    rm -rf "$dir"
    git clone --depth 1 "$repo" "$dir"
  fi
  log "building $pkg (compiles C/C++, takes a minute)"
  R CMD INSTALL --library="$R_LIB" "$dir"
  r_has "$pkg" || die "failed to install $pkg"
}

install_from_git laGP  "$LAGP_REPO"
install_from_git GPEDM "$GPEDM_REPO"

# ------------------------------------------------------------- dev tooling --
# lintr backs `Rscript -e 'lintr::lint("...")'`; nice to have, never fatal.
if ! r_has lintr && apt_usable && apt-cache show r-cran-lintr >/dev/null 2>&1; then
  log "installing lintr via apt"
  apt_install r-cran-lintr || log "lintr install failed (non-fatal)"
fi

# ------------------------------------------------------------------ report --
Rscript -e 'for (p in c("Rcpp","Matrix","tgp","laGP","GPEDM"))
              cat(sprintf("  %-8s %s\n", p, as.character(packageVersion(p))))' \
  | { echo "[setup-gpedm] installed:"; cat; }

log "done - GP-EDM is runnable (see scripts/gpedm-smoke-test.R)"
