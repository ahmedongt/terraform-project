#  YT Thumbnail Downloader (AWS Deployment)

A high-performance, cloud-native web application built to fetch YouTube thumbnails. This project is fully automated using **Infrastructure as Code (IaC)** and hosted on **Amazon Web Services**.

##  Tech Stack
- **Frontend:** HTML5 / Tailwind CSS (Responsive UI)
- **Backend:** Python (Flask API)
- **Infrastructure:** Terraform (Modular & Reusable)
- **Cloud:** AWS (EC2, S3, Networking)
- **Automation:** PowerShell (Custom Deployment Logic)

##  Security & DevSecOps
- **Zero-Secret Policy:** Sensitive `.pem` keys, `terraform.tfvars`, and `.tfstate` files are strictly excluded via `.gitignore`.
- **Infrastructure Auditing:** All changes are version-controlled via Git for a full audit trail.
- **Lightweight Architecture:** Minimalist API design to reduce the attack surface.

##  How to Deploy

### Option A: Manual Deployment 
1. **Initialize:** `terraform init`
2. **Preview Changes:** `terraform plan`
3. **Execute:** `terraform apply`

### Option B: Automated "Fast" Deploy (Recommended)
This project includes a custom automation script that handles the entire lifecycle in ~2 minutes.
```powershell
.\deploy.ps1