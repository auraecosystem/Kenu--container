#!/usr/bin/env bash

# usage: curl -sL https://gist.github.com/grenade/128986996dc588c34ee6c3cbdd1b155a/raw/create-github-runner-quadlet.sh | bash -s ${GITHUB_ORG} ${GITHUB_REPO} ${GITHUB_ACCESS_TOKEN}

sudo mkdir -p /opt/github/runner
for file in Containerfile entrypoint.sh template.env; do
    sudo curl \
        --fail \
        --location \
        --silent \
        --output /opt/github/runner/${file} \
        --url https://gist.github.com/grenade/128986996dc588c34ee6c3cbdd1b155a/raw/${file}
done
sudo curl \
    --fail \
    --location \
    --silent \
    --output /etc/containers/systemd/gh-runner.container \
    --url https://gist.github.com/grenade/128986996dc588c34ee6c3cbdd1b155a/raw/gh-runner.container

sudo groupadd -f podman
sudo mkdir -p /etc/systemd/system/podman.socket.d
sudo curl \
    --fail \
    --location \
    --silent \
    --output /etc/systemd/system/podman.socket.d/override.conf \
    --url https://gist.github.com/grenade/128986996dc588c34ee6c3cbdd1b155a/raw/override.conf

systemctl is-enabled podman.socket || sudo systemctl enable podman.socket
systemctl is-active podman.socket || sudo systemctl start podman.socket

GITHUB_ORG=${1} GITHUB_REPO=${2} GITHUB_ACCESS_TOKEN=${3} RUNNER_NAME=$(hostname -s) envsubst < /opt/github/runner/template.env | sudo tee /opt/github/runner/.env
sudo podman build -t localhost/gh-runner:latest /opt/github/runner
sudo systemctl daemon-reload
sudo systemctl start gh-runner
# journalctl -fu gh-runner
