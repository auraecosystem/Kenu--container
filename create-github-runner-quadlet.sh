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
#   RUNNER_API_TOKEN         (optional PAT for calling GitHub Actions Runner releases API; falls back to anonymous if unset)
#   UBUNTU_VERSION           (optional Ubuntu base image version, defaults to 22.04)
#
# This script:
#   - Resolves the latest revision of this gist and downloads the quadlet artifacts
#   - Queries the GitHub API for the latest Actions Runner release tag
#   - Strips the "v" prefix and passes the version as a build-arg RUNNER_VERSION to podman build
#   - Passes a configurable Ubuntu version as build-arg UBUNTU_VERSION (default 22.04)
#   - Sets up podman.socket and the gh-runner systemd unit

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

if [ -n "${GITHUB_REPO:-}" ] && [ "${GITHUB_REPO}" != "null" ]; then
    GITHUB_URL="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
else
    GITHUB_URL="https://github.com/${GITHUB_ORG}"
fi

GITHUB_ACCESS_TOKEN="${GITHUB_ACCESS_TOKEN}" \
GITHUB_URL="${GITHUB_URL}" \
RUNNER_NAME="${RUNNER_NAME}" \
envsubst < /opt/github/runner/template.env | sudo tee /opt/github/runner/.env >/dev/null

###############################################################################
# Fetch latest GitHub Actions Runner version
###############################################################################
# We call the public GitHub API:
#   GET https://api.github.com/repos/actions/runner/releases/latest
# and extract .tag_name (e.g. "v2.330.0"), then strip the "v" prefix.

runner_releases_api="https://api.github.com/repos/actions/runner/releases/latest"
runner_tag=""

if [ -n "${RUNNER_API_TOKEN:-}" ] && [ "${RUNNER_API_TOKEN}" != "null" ]; then
    runner_tag="$(
        curl \
            --fail \
            --location \
            --silent \
            --header "Authorization: Bearer ${RUNNER_API_TOKEN}" \
            --header 'X-GitHub-Api-Version: 2022-11-28' \
            --url "${runner_releases_api}" \
            | jq --raw-output '.tag_name'
    )" || {
        echo "Error: Failed to fetch latest runner release (authenticated) from ${runner_releases_api}" >&2
        exit 1
    }
else
    runner_tag="$(
        curl \
            --fail \
            --location \
            --silent \
            --header 'X-GitHub-Api-Version: 2022-11-28' \
            --url "${runner_releases_api}" \
            | jq --raw-output '.tag_name'
    )" || {
        echo "Error: Failed to fetch latest runner release (anonymous) from ${runner_releases_api}" >&2
        exit 1
    }
fi

if [ -z "${runner_tag}" ] || [ "${runner_tag}" = "null" ]; then
    echo "Error: Failed to determine latest runner tag from ${runner_releases_api}" >&2
    exit 1
fi

# Strip leading "v" if present, e.g. "v2.330.0" -> "2.330.0"
RUNNER_VERSION="${runner_tag#v}"

if [ -z "${RUNNER_VERSION}" ]; then
    echo "Error: Derived empty RUNNER_VERSION from tag '${runner_tag}'" >&2
    exit 1
fi

echo "Using GitHub Actions Runner version ${RUNNER_VERSION} (tag ${runner_tag})"

###############################################################################
# Determine Ubuntu version to use for base image
###############################################################################
# Default to 22.04 if UBUNTU_VERSION is not set.

UBUNTU_VERSION_DEFAULT="22.04"
UBUNTU_VERSION="${UBUNTU_VERSION:-${UBUNTU_VERSION_DEFAULT}}"

if [ -z "${UBUNTU_VERSION}" ]; then
    echo "Error: UBUNTU_VERSION resolved to empty value" >&2
    exit 1
fi

echo "Using Ubuntu base image version ${UBUNTU_VERSION}"

###############################################################################
# Build the runner image (pass RUNNER_VERSION and UBUNTU_VERSION as build-args)
###############################################################################

if ! sudo podman build \
    --build-arg "RUNNER_VERSION=${RUNNER_VERSION}" \
    --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
    -t localhost/gh-runner:latest \
    /opt/github/runner
then
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
