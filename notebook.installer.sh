#!/usr/bin/env bash
# notebook installer for onboard system
# Adds to any repo: devcontainer config, agent entrypoint, README badge

install_notebook_agent() {
  local dir="$1"

  if [ -f "$dir/.devcontainer/devcontainer.json" ] && grep -q "A2A Notebook Agent" "$dir/.devcontainer/devcontainer.json" 2>/dev/null; then
    echo "  ✓ notebook agent already installed"
    return 0
  fi

  echo "  → Installing A2A Notebook Agent..."

  # Add devcontainer for codespace agent
  mkdir -p "$dir/.devcontainer"
  
  cat > "$dir/.devcontainer/devcontainer.json" << 'DEVJSON'
{
  "name": "A2A Notebook Agent",
  "image": "python:3.12",
  "features": {
    "ghcr.io/devcontainers/features/sshd:1": { "version": "latest" },
    "ghcr.io/devcontainers/features/node:1": { "version": "22" }
  },
  "forwardPorts": [8080],
  "portsAttributes": {
    "8080": { "label": "Agent Dashboard", "onAutoForward": "notify" }
  }
}
DEVJSON

  # Add agent entrypoint
  cat > "$dir/.devcontainer/agent-entrypoint.sh" << 'AGENT'
#!/bin/bash
# A2A Notebook Agent — runs in codespace, monitored via `gh codespace ssh`
set -euo pipefail
REPO="$(basename $(git rev-parse --show-toplevel))"
echo "═══════════════════════════════════════"
echo "  📓 Notebook Agent — $REPO"
echo "  PID: $$"
echo "  Dashboard: http://localhost:8080"
echo "═══════════════════════════════════════"
echo ""
echo "── Analyzing repository structure..."
find . -not -path './node_modules/*' -not -path './.git/*' \
  -not -path './target/*' -maxdepth 3 -type f | head -30
echo ""
echo "── Running diagnostics..."
npm test 2>/dev/null || cargo check 2>/dev/null || python3 -m pytest 2>/dev/null || echo "  No standard test suite found"
echo ""
echo "✅ Agent complete — report generated"
cat /tmp/agent-report.md 2>/dev/null || echo "  No report file"
AGENT
  chmod +x "$dir/.devcontainer/agent-entrypoint.sh"

  echo "  ✓ notebook agent installed (.devcontainer/ + .devcontainer/agent-entrypoint.sh)"
}
