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

  provisioner "shell" {
    inline = [
      "echo '=== Beginning Image Baking Process ==='",
      "sudo dnf update -y",
      "sudo dnf install -y docker aws-cli",
      "sudo systemctl enable docker",
      "sudo curl -L 'https://github.com/docker/compose/releases/latest/download/docker-compose-Linux-x86_64' -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      "sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose",
      "sudo useradd -m ssm-user || true",
      "sudo usermod -a -G docker ec2-user",
      "sudo usermod -a -G docker ssm-user",
      "echo 'ssm-user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ssm-user",
      "sudo chmod 0440 /etc/sudoers.d/ssm-user",
      "echo '=== Image Baking Complete! ==='"
    ]
  }
}
