#!/usr/bin/env bash

# usage: curl -sL https://gist.github.com/grenade/128986996dc588c34ee6c3cbdd1b155a/raw/create-github-runner-quadlet.sh | bash -s ${GITHUB_ACCESS_TOKEN} ${GITHUB_ORG} ${GITHUB_REPO}

gist_id=128986996dc588c34ee6c3cbdd1b155a
gist_api_url=https://api.github.com/gists/${gist_id}

# Determine latest gist revision SHA to avoid cached/older raw URLs
latest_git_sha=$(
    if [ -z "${GITHUB_API_TOKEN}" ] || [ "${GITHUB_API_TOKEN}" = "null" ]; then
        curl \
            --fail \
            --location \
            --silent \
            --header 'X-GitHub-Api-Version: 2022-11-28' \
            --url ${gist_api_url} \
            | jq --raw-output '.history[0].version'
    else
        curl \
            --fail \
            --location \
            --silent \
            --header "Authorization: Bearer ${GITHUB_API_TOKEN}" \
            --header 'X-GitHub-Api-Version: 2022-11-28' \
            --url ${gist_api_url} \
            | jq --raw-output '.history[0].version'
    fi
)

if [ -z "${latest_git_sha}" ] || [ "${latest_git_sha}" = "null" ]; then
    echo "Error: Failed to determine latest gist revision SHA from ${gist_api_url}" >&2
    exit 1
fi

sudo mkdir -p /opt/github/runner
for file in Containerfile entrypoint.sh template.env; do
    sudo curl \
        --fail \
        --location \
        --silent \
        --output /opt/github/runner/${file} \
        --url https://gist.github.com/grenade/${gist_id}/raw/${latest_git_sha}/${file}
done
sudo curl \
    --fail \
    --location \
    --silent \
    --output /etc/containers/systemd/gh-runner.container \
    --url https://gist.github.com/grenade/${gist_id}/raw/${latest_git_sha}/gh-runner.container

sudo groupadd -f podman
sudo mkdir -p /etc/systemd/system/podman.socket.d
sudo curl \
    --fail \
    --location \
    --silent \
    --output /etc/systemd/system/podman.socket.d/override.conf \
    --url https://gist.github.com/grenade/${gist_id}/raw/${latest_git_sha}/override.conf

systemctl is-enabled podman.socket || sudo systemctl enable podman.socket
systemctl is-active podman.socket || sudo systemctl start podman.socket

GITHUB_ACCESS_TOKEN=${1} GITHUB_ORG=${2} GITHUB_REPO=${3} RUNNER_NAME=$(hostname -s) envsubst < /opt/github/runner/template.env | sudo tee /opt/github/runner/.env > /dev/null
sudo podman build -t localhost/gh-runner:latest /opt/github/runner
sudo systemctl daemon-reload
sudo systemctl restart gh-runner || sudo systemctl start gh-runner
# journalctl -fu gh-runner
