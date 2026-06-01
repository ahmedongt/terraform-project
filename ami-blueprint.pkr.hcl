packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "golden_ami" {
  ami_name      = "golden-devops-ami-al2023-{{timestamp}}"
  instance_type = "t3.micro"
  region        = "us-east-1"
  source_ami    = "ami-05b10e08d247fb927"
  ssh_username  = "ec2-user"
  
  tags = {
    Name    = "Golden-Devops-Base-Image"
    Project = "Terraform-Project"
    Engine  = "Packer"
  }
}

build {
  name    = "bake-devops-stack"
  sources = ["source.amazon-ebs.golden_ami"]

  # 1. INDUSTRY STANDARD CODE INJECTION: Copy your workspace directories directly into the image staging path
  provisioner "file" {
    source      = "./"
    destination = "/tmp/app-workspace"
  }

  # Executing via a clean inline script string block to prevent multi-line parsing failure
  provisioner "shell" {
    inline = [
      "echo '=== Beginning Image Baking Process ==='",
      "sudo dnf update -y",
      
      # Install Baseline Packages
      "sudo dnf install -y docker aws-cli python3-pip cronie",
      "sudo systemctl enable docker",
      "sudo systemctl enable crond",
      
      "sudo pip3 install boto3 botocore",
      
      # Setup Docker Compose Plugin natively
      "sudo curl -L 'https://github.com/docker/compose/releases/latest/download/docker-compose-Linux-x86_64' -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose",
      
      # Setup System Users & Permissions safely
      "sudo useradd -m ssm-user || true",
      "sudo usermod -a -G docker ec2-user",
      "sudo usermod -a -G docker ssm-user",
      "echo 'ssm-user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ssm-user",
      "sudo chmod 0440 /etc/sudoers.d/ssm-user",
      
      # Move the staged workspace code into the official operational folder
      "sudo mkdir -p /app/terraform-project",
      "sudo cp -r /tmp/app-workspace/* /app/terraform-project/",
      "sudo rm -rf /tmp/app-workspace",
      
      # Clean up local Git configurations inside the image path to prevent security leakage
      "sudo rm -rf /app/terraform-project/.git*",
      
      # Enforce secure system permissions across operational files
      "sudo chown -R ec2-user:docker /app/terraform-project",
      "sudo chmod -R 755 /app/terraform-project",

      # 2. THE AUTOMATION HEARTBEAT: Write the native Linux systemd service block
      "echo '=== Creating Native App Boot Daemon ==='",
      "echo '[Unit]' | sudo tee /etc/systemd/system/app-stack.service",
      "echo 'Description=Multi-Tier Application Container Stack' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'After=docker.service' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'Requires=docker.service' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo '' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo '[Service]' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'Type=oneshot' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'RemainAfterExit=yes' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'WorkingDirectory=/app/terraform-project' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'ExecStart=/usr/bin/docker-compose up -d' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'ExecStop=/usr/bin/docker-compose down' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo '' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo '[Install]' | sudo tee -a /etc/systemd/system/app-stack.service",
      "echo 'WantedBy=multi-user.target' | sudo tee -a /etc/systemd/system/app-stack.service",

      # Enable the boot unit daemon so it triggers automatically on hardware initiation
      "sudo systemctl daemon-reload",
      "sudo systemctl enable app-stack.service",
      
      "echo '=== Image Baking Complete! ==='"
    ]
  }
}