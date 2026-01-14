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

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = var.environment.name
  }
}

# resource "aws_instance" "web" {
#  ami           = data.aws_ami.app_ami.id
#  instance_type = var.instance_type
#
#  # vpc_security_group_ids = [aws_security_group.web.id]
#  vpc_security_group_ids = [module.web_sg.security_group_id]

#  subnet_id =  module.blog_vpc.public_subnets[0]

#  tags = {
#    Name = "HelloWorld"
#  }
# }

module "web_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"
  name    = "${var.environment.name}-web"

# vpc_id              = data.aws_vpc.default.id
  vpc_id              = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp","https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = [ "all-all" ]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group" "web" {
  name        = "${var.environment.name}-web"
  description = "Allow http and https in web server, and Allow everything out"

  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group_rule"  "web_http_in" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule"  "web_https_in" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule"  "web_everything_out" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.web.id
}

# load balancer

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name    = "${var.environment.name}-blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  # Security Group
  security_groups  = [module.web_sg.security_group_id]

  access_logs = {
    bucket = "my-alb-logs"
  }

  listeners = {
    ex-http-https-redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  target_groups = {
    ex-instance = {
      name_prefix      = "${var.environment.name}-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      target_id        = aws_instance.web.id
    }
  }

  tags = {
    Environment = var.environment.name
    Project     = "Example"
  }
}

# autoscaling
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
}