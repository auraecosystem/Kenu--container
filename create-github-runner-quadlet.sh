#!/usr/bin/env bash

# usage: curl -sL https://gist.github.com/grenade/${gist}/raw/create-github-runner-quadlet.sh | bash

sudo mkdir -p /opt/github/runner
for file in Containerfile entrypoint.sh template.env; do
    sudo curl \
        --fail \
        --location \
        --silent \
        --output /opt/github/runner/${file} \
        --url https://gist.github.com/grenade/${gist}/raw/${file}
done
sudo curl \
    --fail \
    --location \
    --silent \
    --output /etc/containers/systemd/gh-runner.container \
    --url https://gist.github.com/grenade/${gist}/raw/gh-runner.container

systemctl is-enabled podman.socket || sudo systemctl enable podman.socket
systemctl is-active podman.socket || sudo systemctl start podman.socket
