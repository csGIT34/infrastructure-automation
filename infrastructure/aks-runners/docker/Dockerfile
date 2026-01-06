FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_VERSION=2.311.0

RUN apt-get update && apt-get install -y \
        curl \
        wget \
        git \
        jq \
        sudo \
        unzip \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN curl -fsSL https://get.docker.com -o get-docker.sh && \
        sh get-docker.sh && \
        rm get-docker.sh

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Terraform
RUN wget -O- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor | \
        tee /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        tee /etc/apt/sources.list.d/hashicorp.list && \
        apt-get update && \
        apt-get install -y terraform=1.5.* && \
        rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
        install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
        rm kubectl

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Python and dependencies
RUN apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
        pyyaml \
        jsonschema \
        jinja2 \
        azure-identity \
        azure-mgmt-resource \
        azure-servicebus

# Install GitHub Actions Runner
RUN useradd -m -s /bin/bash runner && \
        mkdir -p /actions-runner && \
        chown -R runner:runner /actions-runner

USER runner
WORKDIR /actions-runner

RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
        https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
        tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
        rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

COPY --chown=runner:runner entrypoint.sh /actions-runner/entrypoint.sh
RUN chmod +x /actions-runner/entrypoint.sh

LABEL org.opencontainers.image.source="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
LABEL org.opencontainers.image.description="GitHub Actions Self-Hosted Runner"
LABEL org.opencontainers.image.version="${RUNNER_VERSION}"

ENTRYPOINT ["/actions-runner/entrypoint.sh"]
