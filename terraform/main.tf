##############################################
# Locals – Render User Data Template
##############################################

locals {
  user_data = templatefile("${path.module}/userdata.tpl", {
    website_repo = var.website_repo
    site_ref     = var.site_ref
  })
}

##############################################
# VPC + SUBNETS (Auto-create if not provided)
##############################################

resource "aws_vpc" "this" {
  count      = var.vpc_id == "" ? 1 : 0
  cidr_block = "10.0.0.0/16"
}

data "aws_availability_zones" "az" {}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_ids) > 0 ? 0 : 2
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = cidrsubnet(aws_vpc.this[0].cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.az.names[count.index]
  map_public_ip_on_launch = true
}

locals {
  vpc_id     = var.vpc_id != "" ? var.vpc_id : aws_vpc.this[0].id
  subnet_ids = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : aws_subnet.public[*].id
}

##############################################
# SECURITY GROUPS
##############################################

resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = local.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "instance" {
  name   = "instance-sg"
  vpc_id = local.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.key_name != "" ? ["0.0.0.0/0"] : []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

##############################################
# IAM ROLE + INSTANCE PROFILE
##############################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2" {
  name               = "ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2.name
}

##############################################
# LAUNCH TEMPLATE
##############################################

resource "aws_launch_template" "web" {
  name_prefix   = "static-web-lt-"
  image_id      = var.ami
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  key_name = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.instance.id]
  }

  user_data = base64encode(local.user_data)

  lifecycle {
    create_before_destroy = true
  }
}

##############################################
# ALB + TARGET GROUP
##############################################

resource "aws_lb" "alb" {
  name               = "static-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = local.subnet_ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "static-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

##############################################
# AUTO SCALING GROUP
##############################################

resource "aws_autoscaling_group" "asg" {
  name                = "static-site-asg"
  max_size            = var.asg_max
  min_size            = var.asg_min
  desired_capacity    = var.asg_desired
  vpc_zone_identifier = local.subnet_ids

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 60

  tag {
    key                 = "Name"
    value               = "static-site"
    propagate_at_launch = true
  }

  # Auto Rolling Update when Launch Template changes
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 75
      instance_warmup        = 60
    }

    triggers = ["launch_template"]
  }
}

##############################################
# AUTO SCALING POLICIES
##############################################

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "scale-in"
  autoscaling_group_name = aws_autoscaling_group.asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
}

##############################################
# SNS + CLOUDWATCH ALARMS
##############################################

resource "aws_sns_topic" "alerts" {
  name = "cpu-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  protocol  = "email"
  endpoint  = var.alert_email
  topic_arn = aws_sns_topic.alerts.arn
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"

  alarm_actions = [
    aws_autoscaling_policy.scale_out.arn,
    aws_sns_topic.alerts.arn
  ]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "low-cpu"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 20
  comparison_operator = "LessThanThreshold"

  alarm_actions = [
    aws_autoscaling_policy.scale_in.arn,
    aws_sns_topic.alerts.arn
  ]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }
}

