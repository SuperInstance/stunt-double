# 🏃 Stunt Double — x86_64 Offload Harness

**Spawn an ephemeral x86_64 Codespace for any GitHub repo, run anything, collect results, destroy.**

No config needed. No repo changes required. Works with any language, any build system, any tool.

```bash
./stunt-double.sh SuperInstance/pincher "cargo build --release" target/release/pincher
```

---

## Why

You're on ARM64. Some things need x86:
- **numba/llvmlite** — Basic Pitch, JIT audio
- **Docker multi-arch builds** — amd64 images
- **Binary-only packages** — audio plugins, SDKs
- **Cross-arch testing** — "does it work on x86?"
- **CI/CD staging** — pre-flight before pushing

Stunt Double gives you x86_64 on demand: ~30s cold start, ~$0.0008/sec, zero cleanup.

## Usage

### Basic — just run a command

```bash
./stunt-double.sh owner/repo "npm test"
```

Exit code propagates. Output streams to stdout.

### With artifact extraction

```bash
./stunt-double.sh owner/repo "make build" ./build/output.bin
```

The artifact is copied back to your local machine.

### With config file

```bash
# Repo has .stunt.yml — auto-detected
./stunt-double.sh owner/repo "npm run build" dist/

# Override config
./stunt-double.sh owner/repo "cargo build" --config my-config.yml
```

## Config (`.stunt.yml`)

Drop this in your repo to customize the environment:

```yaml
# .stunt.yml
image: rust:1.85
setup: |
  apt-get update && apt-get install -y libasound2-dev
  cargo fetch
env:
  CI: "true"
  RUSTFLAGS: "-C target-cpu=x86-64-v3"
```

All fields optional. Defaults:
- `image`: `python:3.12`
- `machine`: `basicLinux32gb`
- `idle_timeout`: 10m
- No setup, no env

## How It Works

```
Your machine               Codespace (x86_64)
┌────────────────────┐    ┌────────────────────┐
│ stunt-double.sh    │    │ python:3.12 + sshd │
│                    │    │                    │
│ 1. Create codespace ───▶  (30s boot)        │
│ 2. Wait for ready   │    │                    │
│ 3. Parse .stunt.yml ───▶  Run setup          │
│ 4. Pipe command    ───▶  Execute             │
│ 5. Collect artifact ◀───  Base64/tar stdout  │
│ 6. Destroy           ───▶  Cleanup            │
└────────────────────┘    └────────────────────┘
```

The pipe trick: `gh codespace ssh` joins all args with spaces, breaking `&&`, `|`, etc.
Solution: commands run inside the codespace via a quoting wrapper that preserves shell semantics.

## Patterns

| Command | What it does |
|---------|-------------|
| `"python -m pytest tests/"` | Run test suite on x86 |
| `"cargo build --release"` | Build Rust binary |
| `"docker build -t app . && docker save app > app.tar"` | Build Docker image |
| `"pip install -e . && python benchmark.py"` | Run benchmarks |
| `"./scripts/release.sh"` | Run release pipeline |

## Requirements

- `gh` CLI authenticated with `codespace` scope
- GitHub account with Codespaces access (free tier: 60h/month core, 30h/month)

## Design Principles

1. **Zero coupling** — the target repo has no dependency on stunt-double
2. **One command line** — everything from branch creation to cleanup is a single invocation
3. **Exit code fidelity** — stunt-double exits with the command's exit code
4. **Cost visible** — prints codespace name so you can monitor billing
5. **Fail safe** — always destroys the codespace, even on error
