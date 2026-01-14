data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner]
}

# data "aws_vpc" "default" {
#  default = true
# }

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.environment.name
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs            = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets = [
    "${var.environment.network_prefix}.101.0/24",
    "${var.environment.network_prefix}.102.0/24",
    "${var.environment.network_prefix}.103.0/24"
  ]

  tags = {
    Terraform   = "true"
    Environment = var.environment.name
  }
}

# resource "aws_instance" "web" {
#  ami           = data.aws_ami.app_ami.id
#  instance_type = var.instance_type
#
#  vpc_security_group_ids = [module.web_sg.security_group_id]
#  subnet_id = module.blog_vpc.public_subnets[0]
#
#  tags = {
#    Name = "HelloWorld"
#  }
# }

module "web_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name   = "${var.environment.name}-web"
  # vpc_id              = data.aws_vpc.default.id
  vpc_id = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

################################
# Application Load Balancer
################################

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "${var.environment.name}-blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.web_sg.security_group_id]

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "ex-instance"
      }
    }
  }

  target_groups = {
    ex-instance = {
      name_prefix = "${var.environment.name}-"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"

      health_check = {
        path                = "/"
        interval            = 30
        healthy_threshold   = 2
        unhealthy_threshold = 2
        matcher             = "200-399"
      }
    }
  }

  tags = {
    Environment = var.environment.name
    Project     = "Example"
  }
}

################################
# Auto Scaling Group
################################

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.1.0"

  name     = "${var.environment.name}-blog"
  min_size = var.min_size
  max_size = var.max_size

  vpc_zone_identifier = module.blog_vpc.public_subnets
  security_groups     = [module.web_sg.security_group_id]

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type

  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = module.alb.target_groups["ex-instance"].arn
      traffic_source_type       = "elbv2"
    }
  }
}

