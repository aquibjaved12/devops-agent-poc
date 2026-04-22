# EC2 role

resource "aws_iam_role" "ec2_role" {
  name = "ec2-devops-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

#  Cloudwatch agent permissions

resource "aws_iam_role_policy_attachment" "cw" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# SSM Agent permissions

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2 Instance Profile

resource "aws_iam_instance_profile" "profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ── S3 Full Access — for GitHub Actions CI/CD (Terraform state) ──────
resource "aws_iam_user_policy_attachment" "github_actions_s3" {
  user       = var.github_actions_username
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}