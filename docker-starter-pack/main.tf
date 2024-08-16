terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

data "coder_workspace_owner" "me" {
}

locals {
  username = data.coder_workspace_owner.me.name
}

# dotfiles repo
module "dotfiles" {
    source    = "registry.coder.com/modules/dotfiles/coder"
    agent_id  = coder_agent.main.id
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}

provider "coder" {
}

data "coder_external_auth" "github" {
  id = "lw2773"
  optional = true
}

variable "CODE_VAULT_TOKEN" {
  default = ""
}

resource "coder_script" "jupyterlab" {
  agent_id     = coder_agent.main.id
  display_name = "jupyterlab"
  icon         = "/icon/jupyter.svg"
  script = templatefile("./sh/jupyter_lab_run.sh", {
    LOG_PATH : "/tmp/jupyterlab.log",
    PORT : 19999,
    OWNER : data.coder_workspace_owner.me.name,
    NAME  :  data.coder_workspace.me.name
  })
  run_on_start = true
}

data "coder_parameter" "override_code_vault_token" {
  name        = "CODE_VAULT_ACCESS_TOKEN"
  display_name = "Override Code Vault Access Token"
  description  = "Override the default read only token."
  type        = "string"
  default     = ""
  mutable     = true
}

resource "coder_script" "jupyter-notebook" {
  agent_id     = coder_agent.main.id
  display_name = "jupyter-notebook"
  icon         = "/icon/jupyter.svg"
  script = templatefile("./sh/jupyter_notebook_run.sh", {
    LOG_PATH : "/tmp/jupyter-notebook.log",
    PORT : 19998,
    OWNER : data.coder_workspace_owner.me.name,
    NAME  :  data.coder_workspace.me.name
  })
  run_on_start = true
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os = "linux"
  startup_script_behavior = "blocking"
  startup_script           = <<-EOT
    #!/bin/bash
    set -e

    export PATH="$HOME/.local/bin:$PATH"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

    # Function to log messages
    log() {
      echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    }

    # Install and start code-server
    log "Installing and starting code-server..."
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server 
    nohup /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

    # Install VS Code extensions
    log "Installing VS Code extensions..."
    EXTENSIONS=(
      "ms-python.python"
      "ms-python.black-formatter"
      "ms-toolsai.jupyter"
      "golang.go"
      "christian-kohler.npm-intellisense"
      "xabikos.JavaScriptSnippets"
      "redhat.java"
      "vscjava.vscode-java-debug"
      "dbaeumer.vscode-eslint"
      "esbenp.prettier-vscode"
      "aaron-bond.better-comments"
      "redhat.vscode-yaml"
      "dracula-theme.theme-dracula@2.24.2"
    )
    for ext in "$${EXTENSIONS[@]}"; do
      /tmp/code-server/bin/code-server --install-extension "$ext"
    done

    # Configure VS Code settings
    log "Configuring VS Code settings..."
    VSCODE_SETTINGS=$(cat <<EOF
    {
      "editor.wordWrap": "off",
      "workbench.colorTheme": "Dracula",
      "vim.easymotion": true,
      "vim.highlightedyank.enable": true,
      "vim.leader": " ",
      "vim.useSystemClipboard": true,
      "vim.replaceWithRegister": true,
      "vim.sneak": true,
      "vim.sneakUseIgnorecaseAndSmartcase": true,
      "git.branchValidationRegex": "feature\\.[a-zA-Z0-9]+\\.[0-9]{8}(\\.[a-zA-Z0-9._-]+)?$"
    }
    EOF
    )
    if [ ! -f ~/.local/share/code-server/User/settings.json ]; then
      echo "⚙️ Creating settings file..."
      mkdir -p ~/.local/share/code-server/User
      echo "$${VSCODE_SETTINGS}" > ~/.local/share/code-server/User/settings.json
    fi

    # Install Python libraries
    log "Installing Python libraries..."
    pip install pandas --break-system-packages >/dev/null 2>&1 &

    # Declare TOKEN variable based on OVERRIDE_CODE_VAULT_TOKEN
    if [ -n "$OVERRIDE_CODE_VAULT_TOKEN" ]; then
      TOKEN="$OVERRIDE_CODE_VAULT_TOKEN"
    else
      TOKEN="$CODE_VAULT_TOKEN"
    fi

    # Set up Git credential helper
    log "Setting up Git credential helper..."
    git config --global credential.helper store
    echo "https://$TOKEN:x-oauth-basic@github.com" > ~/.git-credentials
    chmod 600 ~/.git-credentials

    # Clone and set up code_vault repository
    log "Setting up code_vault repository..."
    cd /home/${data.coder_workspace_owner.me.name}/workspace
    if [ ! -d "code_vault" ]; then
      if git clone https://github.com/GeekNOmore/code_vault.git; then
        log "Successfully cloned code_vault repository"
      else
        log "Failed to clone code_vault repository. It might already exist or there might be a network issue."
      fi
    else
      log "code_vault directory already exists. Skipping clone."
      cd code_vault
      git fetch origin
      git reset --hard origin/master  # or whatever your default branch is
      cd ..
    fi
    cd code_vault
    pip install -r requirements.txt --break-system-packages
    python3 ipython_shell/start.py

    # Install custom VS Code extension
    log "Installing custom VS Code extension..."
    GITHUB_USERNAME="GeekNOmore"
    REPO_NAME="core_extension"
    API_URL="https://api.github.com/repos/$GITHUB_USERNAME/$REPO_NAME/releases/latest"
    RELEASE_INFO=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" $API_URL)
    ASSET_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[0].url')
    FILENAME=$(echo "$RELEASE_INFO" | jq -r '.assets[0].name')
    curl -L -H "Authorization: token $TOKEN" -H "Accept: application/octet-stream" -o "$FILENAME" "$ASSET_URL"
    /tmp/code-server/bin/code-server --install-extension "$FILENAME"
    rm "$FILENAME"

    log "Setup completed successfully."
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
    PATH = "$HOME/.local/bin:$PATH"
    OVERRIDE_CODE_VAULT_TOKEN = data.coder_parameter.override_code_vault_token.value,
    CODE_VAULT_TOKEN = var.CODE_VAULT_TOKEN,
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    script       = <<-EOT
      echo "$(cat /proc/loadavg | awk '{print $1}') $(nproc)" | awk '{printf "%0.2f", $1/$2}'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<-EOT
      free -b | awk '/^Swap/ {printf "%.1f/%.1f", $3/1024/1024/1024, $2/1024/1024/1024}'
    EOT
    interval     = 10
    timeout      = 1
  }
}


resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/${local.username}/workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "jupyterlab" {
  agent_id     = coder_agent.main.id
  slug         = "lab"
  display_name = "JupyterLab"
  url          = "http://localhost:19999/@${data.coder_workspace_owner.me.name}/${lower(data.coder_workspace.me.name)}/apps/lab"
  icon         = "/icon/jupyter.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "jupyter-notebook" {
  agent_id     = coder_agent.main.id
  slug         = "notebook"
  display_name = "Jupyter Notebook"
  url          = "http://localhost:19998/@${data.coder_workspace_owner.me.name}/${lower(data.coder_workspace.me.name)}/apps/notebook"
  icon         = "/icon/jupyter.svg"
  subdomain    = false
  share        = "owner"
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "./build"
    build_args = {
      USER = local.username
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}