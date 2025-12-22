#!/bin/bash

set -e

if [ -z "${GITHUB_URL}" ] || [ -z "${GITHUB_ACCESS_TOKEN}" ]; then
    echo "Error: GITHUB_URL and GITHUB_ACCESS_TOKEN must be set."
    exit 1
fi

# Derive the path part after github.com/, stripping any trailing .git
REPO_PATH=$(echo "${GITHUB_URL}" | awk -F'github.com/' '{print $2}' | sed 's/\.git$//')

# Decide whether this is a repo-level or org-level runner
# - If the path contains a slash ("org/repo"), treat it as a repo runner
# - Otherwise, treat it as an org-level runner
if echo "${REPO_PATH}" | grep -q "/"; then
    API_URL_BASE="https://api.github.com/repos/${REPO_PATH}"
    TARGET_TYPE="repository"
else
    API_URL_BASE="https://api.github.com/orgs/${REPO_PATH}"
    TARGET_TYPE="organization"
fi

echo "Configuring runner for ${TARGET_TYPE} '${REPO_PATH}'..."

echo "Generating registration token for ${REPO_PATH}..."
REG_TOKEN=$(curl -sX POST -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
  "${API_URL_BASE}/actions/runners/registration-token" | jq -r .token)

if [ "$REG_TOKEN" == "null" ] || [ -z "$REG_TOKEN" ]; then
    echo "Error: Failed to generate registration token. Check your PAT scopes and GITHUB_URL."
    exit 1
fi

cleanup() {
    echo "Removing runner from ${TARGET_TYPE} '${REPO_PATH}'..."
    REM_TOKEN=$(curl -sX POST -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
      "${API_URL_BASE}/actions/runners/remove-token" | jq -r .token)

    if [ "$REM_TOKEN" == "null" ] || [ -z "$REM_TOKEN" ]; then
        echo "Warning: Failed to generate removal token. Runner may not be deregistered cleanly."
    else
        ./config.sh remove --token "${REM_TOKEN}"
    fi
}

trap 'cleanup; exit 130' SIGINT
trap 'cleanup; exit 143' SIGTERM

echo "Configuring runner..."
./config.sh --unattended \
    --url "${GITHUB_URL}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --work _work \
    --labels "podman" \
    --replace

echo "Starting runner..."
./run.sh & wait $!
