# Cloud-Native YouTube Thumbnail Downloader & Monitor

A fully automated, production-grade 3-tier web architecture. This project showcases **Immutable Infrastructure**, **GitOps CI/CD**, and **Hardened Security** practices.

## 🛠 Tech Stack
* **Cloud Infrastructure:** AWS (EC2, ECR, S3 for state, VPC, IAM).
* **IaC & Automation:** Terraform (Declarative Provisioning), Ansible (Node Orchestration).
* **CI/CD:** GitHub Actions (Automated Build/Scan/Push/Deploy Pipeline).
* **Security:** SonarCloud (SAST), Runtime Secret Injection, Non-Root Containers.
* **Observability:** Prometheus, Grafana, Node Exporter.

## 🏗 System Architecture & Traffic Flow
[Architecture Diagram Description: Cloudflare (Proxy) -> AWS EC2 (Gunicorn/Nginx) -> ECR (Image Storage)]

## 🚀 Key Engineering Highlights

### 1. Immutable CI/CD Pipeline
We replaced manual server-side builds with a **Registry-First** approach. The pipeline builds, tests, scans, and pushes a versioned container image to **Amazon ECR**. The infrastructure uses this immutable artifact, ensuring 100% environment consistency.

### 2. Secure Secret Management
Removed all hardcoded credentials from the configuration. The system now utilizes **GitHub Secrets** for runtime injection, ensuring that sensitive data like Grafana admin credentials and API tokens are never exposed in version control.

### 3. Decoupled Persistence
To ensure resilience against infrastructure tear-downs (`terraform destroy`), we decoupled monitoring data from ephemeral instance storage. Metrics and configuration states are managed to persist independently, allowing for seamless recovery after instance termination.

### 4. Hardened Security Posture
* **Least Privilege:** Implemented non-root Docker containers and IAM Instance Profiles.
* **Shift-Left Security:** Integrated SonarCloud Quality Gates to catch vulnerabilities *before* deployment.
* **Perimeter Defense:** Cloudflare-restricted VPC Security Groups to prevent direct-to-IP traffic.

---
## 📂 Project Structure
├── .github/workflows/          # GitOps Automation Engine
├── ansible/                    # Remote Host Orchestration
├── api/                        # Python Flask Microservice
├── website/                    # Frontend Dashboard
├── docker-compose.yml          # Multi-Container Specification
├── main.tf                     # Infrastructure as Code
└── prometheus.yml              # Monitoring Configuration