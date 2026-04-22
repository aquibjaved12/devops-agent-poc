terraform {
  backend "s3" {
    bucket = "devopsagent-poc-tfstate"
    key    = "poc/terraform.tfstate"
    region = "us-east-1"
  }
}


provider "aws" {
  region = var.region
}

provider "awscc" {
  region = var.region
}

module "vpc" {
  source = "./vpc"

  create_vpc = var.create_vpc
  vpc_cidr   = var.vpc_cidr
}

module "sg" {
  source = "./security_group"

  vpc_id = module.vpc.vpc_id
}

module "iam" {
  source = "./IAM"
  github_actions_username = var.github_actions_username
}

module "ec2" {
  source = "./ec2"

  ami_id            = var.ami_id
  instance_type     = var.instance_type
  subnet_id         = module.vpc.public_subnet_id
  security_group_id = module.sg.sg_id
  iam_instance_profile = module.iam.instance_profile
}

module "cloudwatch" {
  source            = "./cloudwatch"
  instance_id       = module.ec2.instance_id
  log_group_name    = var.log_group_name
  os_log_group_name = var.os_log_group_name
}

module "devops_agent" {
  source = "./devops-agent"

#   region            = var.region
  agent_space_name  = "devops-agent-poc"
}
