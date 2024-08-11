# Use Ubuntu as the base image
FROM ubuntu:latest

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Update and install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    golang \
    sudo \
    vim \
    curl \
    wget \
    software-properties-common \
    unzip \
    locales

# Set the locale
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install Python 3.9
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.9 python3.9-venv python3.9-dev python3-pip

# Install Node.js and npm for React
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    npm install -g npm@latest && \
    npm install -g create-react-app

# Install Java 18
RUN wget -O- https://apt.corretto.aws/corretto.key | apt-key add - && \
    add-apt-repository 'deb https://apt.corretto.aws stable main' && \
    apt-get update && \
    apt-get install -y java-1.8.0-amazon-corretto-jdk

# Install Go
RUN wget https://go.dev/dl/go1.17.6.linux-amd64.tar.gz && \
    tar -xvf go1.17.6.linux-amd64.tar.gz && \
    mv go /usr/local

# Set Go environment variables
ENV GOROOT=/usr/local/go
ENV GOPATH=$HOME/go
ENV PATH=$GOPATH/bin:$GOROOT/bin:$PATH

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Set Rust environment variable
ENV PATH="/root/.cargo/bin:${PATH}"

# Install the latest Gradle
RUN wget https://services.gradle.org/distributions/gradle-7.2-bin.zip -P /tmp && \
    unzip -d /opt/gradle /tmp/gradle-*.zip && \
    rm /tmp/gradle-*.zip

# Set Gradle environment variables
ENV GRADLE_HOME=/opt/gradle/gradle-7.2
ENV PATH=${GRADLE_HOME}/bin:${PATH}

# Set up Git hooks for branch naming convention and push restrictions
RUN mkdir -p /git-hooks && \
    # Pre-commit hook
    echo '#!/bin/bash\n\
branch=$(git rev-parse --abbrev-ref HEAD)\n\
valid_branch_regex="^feature\\.[a-zA-Z0-9]+\\.[0-9]{8}(\\.[a-zA-Z0-9._-]+)?$"\n\
feature_branch_error="All changes should be made on a feature branch. Please create a branch before committing your changes."\n\
if [[ ! $branch =~ $valid_branch_regex ]]; then\n\
    echo "${feature_branch_error}"\n\
    exit 1\n\
fi\n\
exit 0' > /git-hooks/pre-commit && \
    chmod +x /git-hooks/pre-commit && \
    # Pre-push hook
    echo '#!/bin/bash\n\
read local_ref local_sha1 remote_ref remote_sha1\n\
valid_remote_ref_regex="^refs/heads/feature\\.[a-zA-Z0-9]+\\.[0-9]{8}(\\.[a-zA-Z0-9._-]+)?$"\n\
commit_to_non_feat_branch_error="Pushing to '"'"'${remote_ref}'"'"' is not allowed. Please use a feature branch instead."\n\
if [[ ! $remote_ref =~ $valid_remote_ref_regex ]]; then\n\
    echo "${commit_to_non_feat_branch_error}"\n\
    exit 1\n\
fi\n\
exit 0' > /git-hooks/pre-push && \
    chmod +x /git-hooks/pre-push

# Install JupyterLab
# RUN python3.9 -m pip install jupyterlab notebook 

# Clean up
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ARG USER=coder
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
	&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
	&& chmod 0440 /etc/sudoers.d/${USER}
USER ${USER}
WORKDIR /home/${USER}/workspace

RUN git config --global core.hooksPath /git-hooks

# Keep the container running
CMD ["tail", "-f", "/dev/null"]