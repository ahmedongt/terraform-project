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

  # 1. WORKSPACE STAGING: Safely move workspace assets into /tmp
  provisioner "file" {
    source      = "./"
    destination = "/tmp"
  }

  provisioner "shell" {
    inline = [
      "echo '=== Beginning Image Baking Process ==='",
      "sudo dnf update -y",
      
      # Install Baseline Infrastructure Engine Components
      "sudo dnf install -y docker aws-cli python3-pip cronie",
      "sudo systemctl enable docker",
      "sudo systemctl enable crond",
      
      "sudo pip3 install boto3 botocore",
      
      # Install Native Docker Compose Plugin 
      "sudo curl -L 'https://github.com/docker/compose/releases/latest/download/docker-compose-Linux-x86_64' -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose",
      
      # System User & Access Token Layer Adjustments
      "sudo useradd -m ssm-user || true",
      "sudo usermod -a -G docker ec2-user",
      "sudo usermod -a -G docker ssm-user",
      "echo 'ssm-user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ssm-user",
      "sudo chmod 0440 /etc/sudoers.d/ssm-user",
      
      # Initialize runtime directory path
      "sudo mkdir -p /app/terraform-project",
      
      # Move files from staging into production space
      "sudo cp -r /tmp/terraform-project/* /app/terraform-project/ 2>/dev/null || sudo cp -r /tmp/* /app/terraform-project/ 2>/dev/null || true",
      
      # =========================================================================
      # 2. IMMUTABLE PACKER CONTAINER LAYER
      # Pre-compile the custom Backend API container layer during build phase
      # =========================================================================
      "echo '=== Pre-baking Custom Backend API Container Image ==='",
      "sudo systemctl start docker",
      "cd /app/terraform-project",
      "sudo docker build -t devops-backend:latest ./api",
      "sudo systemctl stop docker",
      
      # =========================================================================
      # 3. INDUSTRY-STANDARD MOUNT PERMISSION LAYER
      # Map precise internal Container UIDs to dedicated host storage paths
      # =========================================================================
      "echo '=== Pre-Creating Storage Volumes with Dedicated Container UID Mappings ==='",
      "sudo mkdir -p /app/terraform-project/prometheus_data /app/terraform-project/grafana_data",
      "sudo chown -R 65534:65534 /app/terraform-project/prometheus_data",
      "sudo chown -R 472:472 /app/terraform-project/grafana_data",
      
      # Clean up remaining deployment-time tracking files from temporary space
      "sudo rm -rf /tmp/terraform-project /tmp/ami-blueprint.pkr.hcl /tmp/main.tf",
      "sudo rm -rf /app/terraform-project/.git*",
      "sudo rm -rf /app/terraform-project/api",
      
      # Enforce standard access controls across baseline structural directories
      "sudo chown ec2-user:docker /app/terraform-project",
      "sudo chown -R ec2-user:docker /app/terraform-project/website /app/terraform-project/default.conf /app/terraform-project/prometheus.yml /app/terraform-project/docker-compose.yml 2>/dev/null || true",
      "sudo chmod -R 755 /app/terraform-project",

      # 4. SERVICE ORCHESTRATION: Set up systemd boot configuration unit
      "echo '=== Generating Native Systemd Application Daemon ==='",
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

      "sudo systemctl daemon-reload",
      "sudo systemctl enable app-stack.service",
      
      "echo '=== Image Baking Complete! ==='"
    ]
  }
}


# Extra text for force push ...