# ====================================================================
# FILE: main.tf (Production Automated Zero-Touch Deployment)
# ====================================================================
# [Keep your existing provider and variable declarations here]

# [Keep your existing resources up to aws_iam_role_policy]

resource "aws_iam_role_policy" "s3_and_ssm_access" {
  name = "s3_and_ssm_access"
  role = aws_iam_role.web_admin_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject"]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.website_bucket.arn}",
          "${aws_s3_bucket.website_bucket.arn}/*",
          "arn:aws:s3:::${local.monitoring_bucket}",
          "arn:aws:s3:::${local.monitoring_bucket}/*"
        ]
      },
      {
        # --- CRITICAL FIX: Allows the app to identify its own AWS Account ---
        Action = ["sts:GetCallerIdentity"]
        Effect = "Allow"
        Resource = ["*"]
      }
    ]
  })
}

# [Keep your role attachments]

resource "aws_iam_instance_profile" "web_instance_profile" {
  name = "web_instance_profile_${local.safe_user_name}"
  role = aws_iam_role.web_admin_role.name
}

# [Keep the rest of your file as is]