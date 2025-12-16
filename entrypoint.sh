#!/bin/bash

set -e

if [ -z "${GITHUB_URL}" ] || [ -z "${GITHUB_ACCESS_TOKEN}" ]; then
    echo "Error: GITHUB_URL and GITHUB_ACCESS_TOKEN must be set."
    exit 1
fi

REPO_PATH=$(echo "${GITHUB_URL}" | awk -F'github.com/' '{print $2}' | sed 's/\.git$//')
API_URL_BASE="https://api.github.com/repos/${REPO_PATH}"

if [[ "$REPO_PATH" != *"/"* ]]; then
    API_URL_BASE="https://api.github.com/orgs/${REPO_PATH}"
fi

echo "Generating registration token for ${REPO_PATH}..."

REG_TOKEN=$(curl -sX POST -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
  "${API_URL_BASE}/actions/runners/registration-token" | jq -r .token)

if [ "$REG_TOKEN" == "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "Error: Failed to generate registration token. Check your PAT scopes and GITHUB_URL."
    exit 1
fi

cleanup() {
    echo "Removing runner..."
    REM_TOKEN=$(curl -sX POST -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
      "${API_URL_BASE}/actions/runners/remove-token" | jq -r .token)
      
    ./config.sh remove --token "${REM_TOKEN}"
}

trap 'cleanup; exit 130' SIGINT
trap 'cleanup; exit 143' SIGTERM

echo "Configuring runner..."
./config.sh --unattended \
    --url "${GITHUB_URL}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --work _work \
    --labels "podman,docker" \
    --replace

echo "Starting runner..."
./run.sh & wait $!
