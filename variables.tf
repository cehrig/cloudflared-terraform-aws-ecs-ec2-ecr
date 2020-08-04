variable "cf_cert_pem_path" {
  default = "~/.cloudflared/cert.pem"
}

variable "cf_hostname" {
  default = "aws-ecs-test.ehrig.io"
}

variable "cf_origin" {
  default = "http://httpbin.org"
}

variable "aws_region" {
  default = "eu-central-1"
}

variable "aws_availability_zone" {
  default = "eu-central-1c"
}

variable "aws_secret_name" {
  default = "argo_token"
}

variable "aws_ami_ecs" {
  default = "ami-01b521fb7540d9996"
}

variable "aws_ecs_instance_count" {
  default = "1"
}

variable "aws_ecs_instance_type" {
  default = "t2.medium"
}

variable "aws_ecs_cluster_name" {
  default = "cloudflared_cluster"
}