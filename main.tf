provider "aws" {
  version                 = "~> 2.57"
  region                  = var.aws_region
  shared_credentials_file = var.aws_cred_file_path
}

data "aws_ami" "amazon-ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}



module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git/?ref=v2.44.0"

  name = "ice-vpc"
  cidr = "10.0.0.0/16"

  azs                   = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnet_suffix = "-private"
  private_subnets       = ["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24"]
  public_subnet_suffix  = "-public"
  public_subnets        = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway   = true
  enable_vpn_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "ice-vpc"
    Environment = "dev"
    Description = "VPC for KPMG applications"
  }

}

module "security_groups" {
  source     = "./security_groups"
  vpc_id     = module.vpc.vpc_id
  lb_ingress = var.lb_ingress
}

module "efs" {
  source = "./storage"

  subnet1_id = module.vpc.private_subnets[0]
  subnet2_id = module.vpc.private_subnets[1]
  subnet3_id = module.vpc.private_subnets[2]
  efs-mt1-sg = module.security_groups.efs_mount_1-sg
  efs-mt2-sg = module.security_groups.efs_mount_2-sg
  efs-mt3-sg = module.security_groups.efs_mount_3-sg
}

module "compute" {
  source              = "./compute"
  ami_id              = data.aws_ami.amazon-ami.id
  instance_type       = var.instance_type
  web_sg_id           = module.security_groups.webserver_sg_id
  subnet_webservers   = module.vpc.private_subnets
  vpc_id              = module.vpc.vpc_id
  subnet_loadbalancer = module.vpc.public_subnets
  lb_sg_id            = module.security_groups.lb_sg_id
  efs_id              = module.efs.efs_id
  jumpbox_sg          = module.security_groups.jumpbox-sg
  jumpbox_subnet      = module.vpc.public_subnets[0]
  password            = var.password
}

module "db" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-rds/?ref=v2.20.0"

  identifier = "kpmg-dev"

  engine            = "postgres"
  engine_version    = "9.6.11"
  instance_class    = "db.t3.micro"
  allocated_storage = 5

  name     = "kpmg"
  username = "kpmg_user"
  password = var.db_password
  port     = "5432"

  iam_database_authentication_enabled = true

  vpc_security_group_ids = [module.security_groups.db_sg]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"


  tags = {
    Owner       = "kpmg"
    Environment = "dev"
  }

  # DB subnet group
  subnet_ids = module.vpc.private_subnets

  # DB parameter group
  family = "postgres9.6"

  # DB option group
  major_engine_version = "9.6"
  copy_tags_to_snapshot = "true"
  ca_cert_identifier = "rds-ca-2019"
  final_snapshot_identifier = "rds-final"
  # Database Deletion Protection
  deletion_protection = false


  parameters = [
    {
      name = "rds.force_ssl"
      value = 1
      apply_method = "pending-reboot"
    }
  ]

}


## Outputs

output "load_balancer_dns" {
  value = module.compute.alb_dns
}

output "jumpbox_ip" {
  value = module.compute.jumpbox_ip
}

output "efs_id" {
  value = module.efs.efs_id
}
