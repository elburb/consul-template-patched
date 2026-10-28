# consul-template-patched

Automated orchestration and build repository for [`hashicorp/consul-template`](https://github.com/hashicorp/consul-template) with patches applied to fix critical runtime deadlocks during Vault/OpenBao token renewals.

---

## Why this repository exists

In upstream `consul-template` (v0.37.4 through v0.43.1+), if a transient network failure, DNS delay, or server unavailability occurs while renewing a Vault or OpenBao token, the daemon permanently deadlocks.

### The Bug (Issue [#2058](https://github.com/hashicorp/consul-template/issues/2058) / PR [#2059](https://github.com/hashicorp/consul-template/pull/2059))
* When retries are enabled on failure (`retry { attempts = 0, ... }`), `watch/view.go#L165` attempts to push server errors to an unbuffered channel:
  ```go
  serverErrCh <- err
  ```
* While `runner.watcher` has an error consumer in `manager/runner.go`, **`runner.vaultTokenWatcher.ServerErrCh()` is completely unread**.
* This causes the token renewal goroutine to block indefinitely on the unbuffered channel write.
* The daemon continues running with an active PID under `systemd` (so `Restart=on-failure` never triggers), but **all future token renewals halt silently**. The token in Vault / OpenBao eventually expires at the end of its TTL.

### The Fix
This repository applies [`patches/0001-consume-vault-token-watcher-server-err.patch`](./patches/0001-consume-vault-token-watcher-server-err.patch) (from PR #2059) to `manager/runner.go`, ensuring `vaultTokenWatcher.ServerErrCh()` is properly consumed and drained so exponential retry loops can execute normally.

---

## Releases & Downloads

Pre-built statically linked `linux/amd64` binaries are automatically published on GitHub Releases:

👉 **[Download Latest Patched Release](https://github.com/elburb/consul-template-patched/releases)**

Release tags are named:
```text
${UPSTREAM_TAG}-p.elburb   (e.g. v0.43.1-p.elburb)
```

Each release includes:
* `consul-template_${TAG}-p.elburb_linux_amd64.tar.gz` (contains the standalone `consul-template` static binary)
* `consul-template_${TAG}-p.elburb_linux_amd64.tar.gz.sha256`

---

## Automated Upstream Sync & Release

A GitHub Actions workflow ([`.github/workflows/sync-and-build.yml`](./.github/workflows/sync-and-build.yml)) runs on a daily schedule (`06:00 UTC`):
1. Queries the official `hashicorp/consul-template` releases for the latest version tag.
2. Checks whether a matching `${UPSTREAM_TAG}-p.elburb` release already exists in this repository.
3. If a new upstream release is published, the workflow automatically:
   - Clones the upstream tag.
   - Applies the patch.
   - Runs unit tests.
   - Compiles a static `linux/amd64` binary (`CGO_ENABLED=0`).
   - Packages and creates a new GitHub Release with binary assets and checksums.

You can also trigger a build manually anytime via **Actions → Upstream Sync & Patched Release → Run workflow** (with optional custom tag and force-rebuild inputs).

---

## Local Building

To build the patched binary locally:

### Prerequisites
* Go 1.23+
* Git, Make, Patch

### Build Commands
```bash
# Build binary for default upstream tag (v0.43.1)
make build

# Build a specific upstream tag
make build TAG=v0.43.1

# Run unit tests
make test

# Clean build artifacts
make clean
```

Compiled binaries and checksums are generated in the `bin/` directory:
```text
bin/consul-template_v0.43.1-p.elburb_linux_amd64
bin/consul-template -> symlink to compiled binary
```

---

## Quick Server Installation

To deploy the compiled binary to a server:

```bash
# 1. Download release
TAG="v0.43.1-p.elburb"
curl -sSL -o consul-template.tar.gz \
  "https://github.com/elburb/consul-template-patched/releases/download/${TAG}/consul-template_${TAG}_linux_amd64.tar.gz"

# 2. Extract and install
tar -xzf consul-template.tar.gz
sudo install -m 0755 consul-template /usr/local/bin/consul-template

# 3. Verify
consul-template -v

# 4. Restart service if running under systemd
sudo systemctl restart consul-template.service
```

---

## License

The patch and orchestration scripts in this repository are licensed under the same license as the upstream project (Mozilla Public License 2.0).
