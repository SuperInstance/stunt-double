#!/usr/bin/env bash
# stunt-double.sh — General-purpose x86_64 offload harness
#
# Spawns an ephemeral Codespace for any repo, runs a command, returns artifacts.
# The repo doesn't need to know about stunt-double — it just needs to exist.
#
# Usage:
#   ./stunt-double.sh <repo> "<command>"               # Run command, return exit code
#   ./stunt-double.sh <repo> "<command>" <artifact>     # Also extract artifact
#   ./stunt-double.sh <repo> "<command>" <artifact> --config <config>
#
# Examples:
#   ./stunt-double.sh SuperInstance/pincher "cargo build --release" target/release/pincher
#   ./stunt-double.sh SuperInstance/opensmile-bridge "python -m pytest tests/" 
#   ./stunt-double.sh user/repo "cat Makefile | head -20"
#
# Config (auto-detected from repo's .stunt.yml or overridden):
#   image: python:3.12        # Devcontainer base image
#   setup: pip install -r requirements.txt  # One-time setup
#   machine: basicLinux32gb   # Codespace machine type

set -euo pipefail

# ─── Config ───────────────────────────────────────────────

REPO="${1:?Usage: stunt-double.sh <repo> <command> [artifact] [--config <file>]}"
CMD="${2:?}"
ARTIFACT="${3:-}"
CONFIG_FILE="${4:-}"

# Generate unique identifiers
BRANCH="stunt-$(date +%s)-$((RANDOM % 1000))"
NAME="sd-$(basename "$REPO")-$(date +%s | tail -c 9)"
TIMEOUT=1200  # 20 min max

# Auto-detect config from repo, or use defaults
if [ -z "$CONFIG_FILE" ]; then
  CONFIG_FILE=".stunt.yml"
fi

echo "═══ STUNT DOUBLE ═══"
echo "→ Repo:      $REPO"
echo "→ Command:   $CMD"
echo "→ Artifact:  ${ARTIFACT:-"(none)"}"
echo "→ Config:    ${CONFIG_FILE}"
echo ""

# ─── Phase 1: Create Codespace ────────────────────────────

echo "→ [1/5] Creating codespace: $NAME"

CODESPACE=$(gh codespace create \
  --repo "$REPO" \
  --branch "$BRANCH" \
  --machine basicLinux32gb \
  --idle-timeout 10m \
  --wait-timeout "$TIMEOUT" \
  --display-name "$NAME" \
  2>&1 | tail -1)

echo "   Codespace: $CODESPACE"

# ─── Phase 2: Wait for Readiness ──────────────────────────

echo "→ [2/5] Waiting for availability..."
gh codespace wait --codespace "$CODESPACE" --timeout "$TIMEOUT" >/dev/null 2>&1

# ─── Phase 3: Detect Config & Run Setup ───────────────────

echo "→ [3/5] Checking for config..."

# The trick: pipe commands to avoid gh arg-joining issue
# First, check if .stunt.yml exists, parse setup commands
SETUP=$(gh codespace ssh --codespace "$CODESPACE" -- "
  if [ -f \"$CONFIG_FILE\" ]; then
    grep '^setup:' \"$CONFIG_FILE\" | sed 's/^setup: *//'
  else
    echo 'none'
  fi
" 2>/dev/null)

if [ -n "$SETUP" ] && [ "$SETUP" != "none" ]; then
  echo "   Setup found: $SETUP"
  echo "   Running setup..."
  gh codespace ssh --codespace "$CODESPACE" -- "cd /workspaces/$(basename "$REPO" .git) && $SETUP" 2>/dev/null
else
  echo "   No setup config found, skipping"
fi

# ─── Phase 4: Run Command ─────────────────────────────────

echo "→ [4/5] Running command..."

# Write the command to a temp script to handle pipes, redirects, etc.
gh codespace ssh --codespace "$CODESPACE" -- "
  cd /workspaces/$(basename "$REPO" .git) && $CMD
" 2>/dev/null || true  # Don't fail yet, we might still need to collect artifacts

EXIT_CODE=$?
echo "   Exit code: $EXIT_CODE"

# ─── Phase 5: Collect Artifact (if specified) ─────────────

if [ -n "$ARTIFACT" ]; then
  echo "→ [5/5] Collecting artifact: $ARTIFACT"
  
  mkdir -p "$(dirname "$ARTIFACT")"
  gh codespace ssh --codespace "$CODESPACE" -- "
    if [ -f \"$ARTIFACT\" ]; then
      cat '$ARTIFACT' | base64
    elif [ -d \"$ARTIFACT\" ]; then
      cd \"$ARTIFACT\" && tar czf - .
    else
      echo 'ARTIFACT_NOT_FOUND'
    fi
  " 2>/dev/null > /tmp/stunt-artifact.b64
  
  # Detect and decode
  if head -1 /tmp/stunt-artifact.b64 | grep -q '^[A-Za-z0-9+/=]\{100,\}$'; then
    # It's base64 — single file
    mkdir -p "$(dirname "$ARTIFACT")" 
    base64 -d < /tmp/stunt-artifact.b64 > "$ARTIFACT"
    echo "   Artifact saved: $ARTIFACT ($(wc -c < "$ARTIFACT") bytes)"
  elif head -1 /tmp/stunt-artifact.b64 | grep -q '^ARTIFACT_NOT_FOUND$'; then
    echo "   ⚠️ Artifact not found at: $ARTIFACT"
  else
    # Might be tar or raw output
    echo "   Artifact output:"
    head -5 /tmp/stunt-artifact.b64
  fi
  
  rm -f /tmp/stunt-artifact.b64
fi

# ─── Cleanup ──────────────────────────────────────────────

echo "→ Cleaning up codespace..."
gh codespace delete --codespace "$CODESPACE" --force >/dev/null 2>&1 || true
echo "→ Codespace destroyed"

echo ""
echo "═══ DONE (exit: $EXIT_CODE) ═══"
exit $EXIT_CODE
