#!/usr/bin/env bash

# usage: curl -sL https://gist.github.com/grenade/128986996dc588c34ee6c3cbdd1b155a/raw/create-github-runner-quadlet.sh | bash -s ${GITHUB_ACCESS_TOKEN} ${GITHUB_ORG} ${GITHUB_REPO}
#
# Arguments:
#   $1 - GITHUB_ACCESS_TOKEN (PAT used by the runner)
#   $2 - GITHUB_ORG          (GitHub organization, e.g. "helexa-ai")
#   $3 - GITHUB_REPO         (optional, GitHub repo name for repo-level runner)
#
# Optional env:
#   GITHUB_API_TOKEN         (optional PAT for calling GitHub Gist API; falls back to anonymous if unset)

set -euo pipefail

###############################################################################
# Basic argument validation
###############################################################################

GITHUB_ACCESS_TOKEN="${1:-}"
GITHUB_ORG="${2:-}"
GITHUB_REPO="${3:-}"

if [ -z "${GITHUB_ACCESS_TOKEN}" ]; then
    echo "Error: GITHUB_ACCESS_TOKEN (arg 1) is required." >&2
    echo "Usage: bash -s <GITHUB_ACCESS_TOKEN> <GITHUB_ORG> [GITHUB_REPO]" >&2
    exit 1
fi

if [ -z "${GITHUB_ORG}" ]; then
    echo "Error: GITHUB_ORG (arg 2) is required." >&2
    echo "Usage: bash -s <GITHUB_ACCESS_TOKEN> <GITHUB_ORG> [GITHUB_REPO]" >&2
    exit 1
fi

###############################################################################
# Resolve latest gist revision SHA
###############################################################################

gist_id="128986996dc588c34ee6c3cbdd1b155a"
gist_api_url="https://api.github.com/gists/${gist_id}"

# For quiet success, only print detailed info on failure.
# We still echo the resolved SHA once so we can see what was used if needed.
if [ -n "${GITHUB_API_TOKEN:-}" ] && [ "${GITHUB_API_TOKEN}" != "null" ]; then
    latest_git_sha="$(
        curl \
            --fail \
            --location \
            --silent \
            --header "Authorization: Bearer ${GITHUB_API_TOKEN}" \
            --header 'X-GitHub-Api-Version: 2022-11-28' \
            --url "${gist_api_url}" \
            | jq --raw-output '.history[0].version'
    )" || {
        echo "Error: Failed to fetch gist metadata with authenticated request from ${gist_api_url}" >&2
        exit 1
    }
else
    latest_git_sha="$(
        curl \
            --fail \
            --location \
            --silent \
            --header 'X-GitHub-Api-Version: 2022-11-28' \
            --url "${gist_api_url}" \
            | jq --raw-output '.history[0].version'
    )" || {
        echo "Error: Failed to fetch gist metadata (anonymous) from ${gist_api_url}" >&2
        exit 1
    }
fi

if [ -z "${latest_git_sha}" ] || [ "${latest_git_sha}" = "null" ]; then
    echo "Error: Failed to determine latest gist revision SHA from ${gist_api_url}" >&2
    exit 1
fi

echo "Using gist ${gist_id} revision ${latest_git_sha}"

###############################################################################
# Download artifacts from the resolved gist revision
###############################################################################

base_gist_raw_url="https://gist.github.com/grenade/${gist_id}/raw/${latest_git_sha}"

sudo mkdir -p /opt/github/runner || {
    echo "Error: Failed to create /opt/github/runner" >&2
    exit 1
}

for file in Containerfile entrypoint.sh template.env; do
    target="/opt/github/runner/${file}"
    url="${base_gist_raw_url}/${file}"

    if ! sudo curl \
        --fail \
        --location \
        --silent \
        --output "${target}" \
        --url "${url}"
    then
        echo "Error: Failed to download ${file} from ${url}" >&2
        exit 1
    fi
done

quadlet_target="/etc/containers/systemd/gh-runner.container"
quadlet_url="${base_gist_raw_url}/gh-runner.container"

if ! sudo curl \
    --fail \
    --location \
    --silent \
    --output "${quadlet_target}" \
    --url "${quadlet_url}"
then
    echo "Error: Failed to download gh-runner.container from ${quadlet_url}" >&2
    exit 1
fi

sudo groupadd -f podman || {
    echo "Error: Failed to ensure podman group exists" >&2
    exit 1
}

sudo mkdir -p /etc/systemd/system/podman.socket.d || {
    echo "Error: Failed to create /etc/systemd/system/podman.socket.d" >&2
    exit 1
}

override_target="/etc/systemd/system/podman.socket.d/override.conf"
override_url="${base_gist_raw_url}/override.conf"

if ! sudo curl \
    --fail \
    --location \
    --silent \
    --output "${override_target}" \
    --url "${override_url}"
then
    echo "Error: Failed to download override.conf from ${override_url}" >&2
    exit 1
fi

###############################################################################
# Ensure podman.socket is enabled and active
###############################################################################

if ! systemctl is-enabled podman.socket >/dev/null 2>&1; then
    if ! sudo systemctl enable podman.socket; then
        echo "Error: Failed to enable podman.socket" >&2
        exit 1
    fi
fi

if ! systemctl is-active podman.socket >/dev/null 2>&1; then
    if ! sudo systemctl start podman.socket; then
        echo "Error: Failed to start podman.socket" >&2
        exit 1
    fi
fi

###############################################################################
# Generate runner env file
###############################################################################

RUNNER_NAME="$(hostname -s)"

GITHUB_ORG="${GITHUB_ORG}" \
GITHUB_REPO="${GITHUB_REPO}" \
RUNNER_NAME="${RUNNER_NAME}" \
envsubst < /opt/github/runner/template.env | sudo tee /opt/github/runner/.env >/dev/null

###############################################################################
# Build the runner image
###############################################################################

if ! sudo podman build -t localhost/gh-runner:latest /opt/github/runner; then
    echo "Error: podman build of localhost/gh-runner:latest failed" >&2
    exit 1
fi

###############################################################################
# Reload systemd and start/restart gh-runner service
###############################################################################

if ! sudo systemctl daemon-reload; then
    echo "Error: systemctl daemon-reload failed" >&2
    exit 1
fi

if ! sudo systemctl restart gh-runner 2>/dev/null; then
    # If restart fails because the service doesn't exist yet, try start
    if ! sudo systemctl start gh-runner; then
        echo "Error: Failed to start gh-runner systemd service" >&2
        exit 1
    fi
fi

# At this point, things are working as expected; no further noisy output.
