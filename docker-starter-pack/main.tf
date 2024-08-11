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
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server 
    nohup /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

    # python extension
    /tmp/code-server/bin/code-server --install-extension ms-python.python
    /tmp/code-server/bin/code-server --install-extension ms-python.black-formatter
    /tmp/code-server/bin/code-server --install-extension ms-toolsai.jupyter

    # go
    /tmp/code-server/bin/code-server --install-extension golang.go

    # react
    /tmp/code-server/bin/code-server --install-extension christian-kohler.npm-intellisense
    /tmp/code-server/bin/code-server --install-extension xabikos.JavaScriptSnippets

    # java
    /tmp/code-server/bin/code-server --install-extension redhat.java
    /tmp/code-server/bin/code-server --install-extension vscjava.vscode-java-debug
    # /tmp/code-server/bin/code-server --install-extension vscjava.vscode-gradle  no release version

    # other util
    /tmp/code-server/bin/code-server --install-extension dbaeumer.vscode-eslint
    /tmp/code-server/bin/code-server --install-extension esbenp.prettier-vscode
    /tmp/code-server/bin/code-server --install-extension aaron-bond.better-comments
    /tmp/code-server/bin/code-server --install-extension redhat.vscode-yaml
    /tmp/code-server/bin/code-server --install-extension dracula-theme.theme-dracula@2.24.2
    # /tmp/code-server/bin/code-server --install-extension hashicorp.terraform 

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
    pip3 install --user pandas >/dev/null 2>&1 &

  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
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
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
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
