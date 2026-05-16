# Cloud-Native YouTube Thumbnail Downloader & Monitor

A fully automated, production-grade 3-tier web application built to fetch, serve, and manage YouTube thumbnails. This project demonstrates advanced practices in **Infrastructure as Code (IaC)**, **Configuration Management**, secure cloud networking, **GitOps CI/CD pipelines**, and live production system monitoring.

## 🛠 Tech Stack & Tools

* **Frontend:** Responsive Web Interface (HTML5, Tailwind CSS, JavaScript).
* **Backend:** REST API Microservice (Python Flask, Pytest, Gunicorn).
* **Infrastructure Layer:** Declarative cloud provisioning via HashiCorp Terraform.
* **Configuration & Orchestration:** Ansible Playbooks and Multi-Container Docker Compose.
* **Networking & Security:** Cloudflare Edge Proxy Routing, AWS Security Groups, and IAM Instance Profiles.
* **Continuous Integration:** GitHub Actions Pipelines integrated with SonarCloud Quality Gates.
* **Observability Suite:** Prometheus Metrics Scraper, Node Exporter, and Grafana Visualization Dashboards.

---

## 🏗 System Architecture & Traffic Flow

```text
[ Client Request ] ──► [ Cloudflare Edge Proxy ]
                                  │
                                  ▼ (Ports 80 / 443 Allowed Only From Cloudflare IPs)
                       [ AWS Elastic IP / EC2 Instance ]
                                  │
                                  ▼
                     [ Nginx Reverse Proxy Container ] (Port 80)
                        /                       \
                       /                         \
                      ▼                           ▼
        [ Flask API Container ] (Port 5000)   [ Monitoring Services ]
          - Extracts YouTube Video ID           - Prometheus (Port 9090)
          - Downloads & Caches Assets           - Grafana (Port 3000)
          - Serves / Deletes Files Securely     - Node Exporter (Metrics)


Key Architectural Highlights
Cloudflare Perimeter Firewall: The AWS Security Group dynamically reads Cloudflare’s official public IP ranges at runtime. It restricts inbound web traffic strictly to Cloudflare proxy nodes, protecting the backend origin server from direct-to-IP DDoS vectors and malicious scans.

State & Metric Recovery Vault: Container data directories for Prometheus and Grafana are securely mounted on the host using Ansible. To prevent telemetry loss, automated backup scripts synchronize configuration and metric states to an isolated AWS S3 storage bucket.


Project Structure


├── .github/workflows/          # GitOps Automation Engine
│   ├── terraform-cicd.yml      # Main Test, Build, and Deploy Workflow
│   └── terraform-destroy.yml   # On-Demand Cloud Teardown Workflow
├── ansible/
│   └── deploy.yml              # Remote Host Orchestration & Docker Stack Setup
├── api/                        # Microservice Backend Layer
│   ├── app.py                  # Core Thumbnail Downloader & Management API
│   ├── Dockerfile              # Multi-stage Containerization Setup
│   └── test_app.py             # Unit and Functional Testing (Pytest)
├── website/                    # Static UI Frontend Layer
│   └── index.html              # Frontend Dashboard styled with Tailwind CSS
├── default.conf                # Nginx Reverse Proxy Routing Configuration
├── docker-compose.yml          # Multi-Container Application Stack Specification
├── main.tf                     # Core Cloud Infrastructure Resources Manifest
├── prometheus.yml              # Real-Time Metrics Collection Settings
└── sonar-project.properties    # Code Analysis & Scanning Directives




CI/CD GitOps Workflow
Every structural code check-in or code merge onto the main branches triggers the automated GitHub Actions CI/CD Engine:

Test Phase: Initializes a Python runtime, installs application requirements, runs automated unit testing via pytest, and outputs a test coverage report (coverage.xml).

Quality Gate: Passes project telemetry to SonarCloud to analyze code health, vulnerabilities, and security flaws.

Infrastructure Phase: Runs automated checks (terraform init, fmt, validate) and generates an execution blueprint plan (terraform plan).

Deployment Phase: Provisions or updates target cloud infrastructure on AWS synchronously, then hands control over to Ansible to securely configure host settings, launch the application containers using Docker Compose, and apply production monitoring rules.





Security Posture & Least-Privilege Access
Zero Secret Footprint: Sensitive authentication files (*.pem), variable assignments (terraform.tfvars), and runtime state logs are strictly isolated via local root .gitignore configuration rules to ensure no production secrets are committed to version control.

IAM Role Attachment: The host virtual machine assumes configurations dynamically through an assigned AWS IAM Instance Profile role, allowing the server to write database and metric logs to S3 securely without requiring hardcoded static cloud access keys on disk.
