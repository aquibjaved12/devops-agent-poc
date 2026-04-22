resource "aws_instance" "ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.iam_instance_profile

  user_data                   = file("${path.module}/userdata.sh")
  user_data_replace_on_change = true

  tags = {
    Name = "devops-agent-poc"
  }
}