# Custom GitHub Actions Runner Image with Infrastructure Tools
# For use with local k3s cluster

FROM summerwind/actions-runner:latest

USER root

# Install infrastructure tools
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    gnupg \
    lsb-release \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Terraform
RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && \
    apt-get install -y terraform && \
    rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Python packages for infrastructure automation
RUN pip3 install --no-cache-dir --break-system-packages \
    pyyaml \
    jsonschema \
    jinja2 \
    azure-identity \
    azure-mgmt-resource \
    azure-servicebus \
    azure-cosmos \
    requests \
    click

# Setup Terraform plugin cache directory in /tmp (writable by runner)
# Using /tmp because the base image's init script overwrites /home/runner/.terraform.d
RUN mkdir -p /tmp/terraform-plugin-cache && \
    chmod 777 /tmp/terraform-plugin-cache

# Set Terraform plugin cache environment variable
ENV TF_PLUGIN_CACHE_DIR=/tmp/terraform-plugin-cache

USER runner

# Labels
LABEL org.opencontainers.image.description="GitHub Actions Runner with Infrastructure Tools"
LABEL org.opencontainers.image.source="https://github.com/infrastructure-automation"
LABEL org.opencontainers.image.version="1.1.0"
