# aws-ash-cluster — Terraform for AWS AI Cluster
# Deploys: head node (API gateway) + N worker nodes (Ollama) + vector DB node (Qdrant)
# Uses spot instances for cost savings

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  cluster_name = "ash-cluster-${var.cluster_name_suffix}"
  common_tags = {
    Project     = "ash-cluster"
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

# VPC and networking
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true

  tags = local.common_tags
}

# Security group
resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-sg"
  description = "ash cluster security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Ollama API"
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Qdrant HTTP"
    from_port   = 6333
    to_port     = 6334
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "Consul"
    from_port   = 8300
    to_port     = 8600
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# SSH key pair
resource "tls_private_key" "cluster" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "cluster" {
  key_name   = "${local.cluster_name}-key"
  public_key = tls_private_key.cluster.public_key_openssh
}

# IAM role for EC2 instances
resource "aws_iam_role" "cluster" {
  name = "${local.cluster_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
}

resource "aws_iam_instance_profile" "cluster" {
  name = "${local.cluster_name}-profile"
  role = aws_iam_role.cluster.name
}

# Head node (API gateway + router)
resource "aws_instance" "head" {
  count = var.head_node_count

  ami                    = data.aws_ami.arch.id
  instance_type          = var.head_instance_type
  key_name               = aws_key_pair.cluster.key_name
  subnet_id              = element(module.vpc.public_subnets, count.index % length(module.vpc.public_subnets))
  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.cluster.name

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.head_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data-head.sh", {
    cluster_name = local.cluster_name
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-head-${count.index + 1}"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# Worker nodes (Ollama) — spot instances
resource "aws_spot_instance_request" "worker" {
  count = var.worker_node_count

  ami                    = data.aws_ami.arch.id
  instance_type          = var.worker_instance_type
  key_name               = aws_key_pair.cluster.key_name
  subnet_id              = element(module.vpc.private_subnets, count.index % length(module.vpc.private_subnets))
  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.cluster.name

  spot_price                      = var.worker_spot_max_price
  spot_type                       = "persistent"
  instance_interruption_behavior  = "stop"
  wait_for_fulfillment            = true

  root_block_device {
    volume_size = var.worker_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data-worker.sh", {
    cluster_name = local.cluster_name
    node_type    = "ollama"
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-worker-${count.index + 1}"
  })

  lifecycle {
    ignore_changes = [ami, spot_price]
  }
}

# Vector DB node (Qdrant)
resource "aws_instance" "vectordb" {
  count = var.vectordb_node_count

  ami                    = data.aws_ami.arch.id
  instance_type          = var.vectordb_instance_type
  key_name               = aws_key_pair.cluster.key_name
  subnet_id              = element(module.vpc.private_subnets, count.index % length(module.vpc.private_subnets))
  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.cluster.name

  root_block_device {
    volume_size = var.vectordb_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data-worker.sh", {
    cluster_name = local.cluster_name
    node_type    = "qdrant"
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vectordb-${count.index + 1}"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# ALB for Ollama API
resource "aws_lb" "ollama" {
  name               = "${local.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.cluster.id]
  subnets            = module.vpc.public_subnets
  tags               = local.common_tags
}

resource "aws_lb_target_group" "ollama" {
  name     = "${local.cluster_name}-tg-ollama"
  port     = 11434
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  tags     = local.common_tags

  health_check {
    path                = "/api/tags"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "ollama" {
  load_balancer_arn = aws_lb.ollama.arn
  port              = 11434
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ollama.arn
  }
}

resource "aws_lb_target_group_attachment" "ollama" {
  count            = var.worker_node_count
  target_group_arn = aws_lb_target_group.ollama.arn
  target_id        = aws_spot_instance_request.worker[count.index].spot_instance_id
  port             = 11434
}

# Outputs
output "head_node_public_ip" {
  value = aws_instance.head[*].public_ip
}

output "ollama_api_endpoint" {
  value = "http://${aws_lb.ollama.dns_name}:11434"
}

output "ssh_private_key" {
  value     = tls_private_key.cluster.private_key_pem
  sensitive = true
}

output "cluster_name" {
  value = local.cluster_name
}
