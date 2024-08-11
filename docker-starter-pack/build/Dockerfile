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
    unzip

# Install Python 3.9
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.9 python3.9-venv python3.9-dev python3-pip

# Install Node.js and npm for React
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
    apt-get install -y nodejs && \
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

# set up global git hook to prevent from commiting to master
RUN mkdir -p /git-hooks && \
    echo '#!/bin/bash\n\
while read oldrev newrev refname\n\
do\n\
  if [[ $refname = "refs/heads/master" ]] ; then\n\
    echo "Direct pushes to master are not allowed. Please use a pull request."\n\
    exit 1\n\
  fi\n\
done' > /git-hooks/pre-receive && \
    chmod +x /git-hooks/pre-receive

RUN git config --global core.hooksPath /git-hooks

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
WORKDIR /home/${USER}

# Keep the container running
CMD ["tail", "-f", "/dev/null"]
