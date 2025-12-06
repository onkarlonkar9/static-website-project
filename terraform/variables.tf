variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "ami" {
  type    = string
  default = "ami-0ecb62995f68bb549"
}

variable "key_name" {
  type    = string
  default = "e-com"
}

variable "website_repo" {
  type    = string
  default = "https://github.com/sruthi234/static-website-project.git"
}

variable "site_ref" {
  type    = string
  default = "main"
}

variable "asg_min" {
  type    = number
  default = 1
}

variable "asg_desired" {
  type    = number
  default = 1
}

variable "asg_max" {
  type    = number
  default = 3
}

variable "alert_email" {
  type    = string
  default = "onkarlonkar018@gmail.com"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "public_subnet_ids" {
  type    = list(string)
  default = []
}

