FROM ubuntu:${UBUNTU_VERSION}

ARG UBUNTU_VERSION=22.04
ARG RUNNER_VERSION=2.330.0

ENV DEBIAN_FRONTEND=noninteractive
ENV UBUNTU_VERSION=${UBUNTU_VERSION}
ENV RUNNER_VERSION=${RUNNER_VERSION}

# 1. Install base dependencies
RUN apt-get update && apt-get install -yqq --no-install-recommends \
    curl \
    jq \
    git \
    unzip \
    tar \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Docker CLI
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -yqq docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# 3. Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -yqq gh && \
    rm -rf /var/lib/apt/lists/*

# 4. Create runner user
RUN groupadd -g 1001 podman && \
    useradd -m runner -s /bin/bash && \
    usermod -aG podman runner && \
    echo "runner ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER runner
WORKDIR /home/runner

# 5. Download Runner
RUN curl -o runner.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf ./runner.tar.gz && \
    rm runner.tar.gz

# 6. Install runner dependencies
USER root
RUN ./bin/installdependencies.sh && \
    rm -rf /var/lib/apt/lists/*

# 7. Setup Entrypoint
COPY --chown=runner:runner entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
