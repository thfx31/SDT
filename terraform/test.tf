terraform {
  cloud {
    organization = "STD"

    workspaces {
      name = "STD"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

data "aws_ami" "ecs_optimized_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.202*-x86_64-ebs"]
  }
}

resource "aws_security_group" "allow_http_ssh" {
  name        = "std-allow-http-ssh"
  description = "Security group to allow HTTP and SSH access"

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH traffic"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "elasticache_sg" {
  name        = "std-elasticache-sg"
  description = "Security group for Elasticache"

  ingress {
    description = "Allow inbound traffic from EC2 instances"
    from_port   = 11211
    to_port     = 11211
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_cluster" "elasticache" {
  cluster_id      = "std-elasticache"
  engine          = "redis"
  node_type       = "cache.t2.micro"
  num_cache_nodes = 1

  security_group_ids = [aws_security_group.elasticache_sg.id]
}

resource "aws_instance" "ecs_instance" {
  vpc_security_group_ids = [aws_security_group.allow_http_ssh.id]

  ami           = data.aws_ami.ecs_optimized_ami.id
  instance_type = "t2.micro"
  key_name      = "SRE-KeyPair"

  user_data = <<-EOF
              #!/bin/bash
              docker pull ghcr.io/thfx31/std/chat-server:latest
              docker run -d -p 80:3000 \
                -e ELASTICACHE_ENDPOINT=${aws_elasticache_cluster.elasticache.configuration_endpoint} \
                -e ELASTICACHE_PORT=11211 \
                ghcr.io/thfx31/std/chat-server:latest
              EOF

  depends_on = [aws_elasticache_cluster.elasticache]

  tags = {
    Name = "STD-EC2"
  }
}

output "elasticache_endpoint" {
  value = aws_elasticache_cluster.elasticache.configuration_endpoint
}
