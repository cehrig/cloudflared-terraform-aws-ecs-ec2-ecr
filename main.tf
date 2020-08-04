provider "aws" {
  version = "3.0.0"
  region = var.aws_region
  access_key = "<...>"
  secret_key = "<...>"
}

resource "aws_secretsmanager_secret" "cert_pem" {
  name = var.aws_secret_name
}

resource "aws_secretsmanager_secret_version" "cert_pem" {
  secret_id     = aws_secretsmanager_secret.cert_pem.id
  secret_string = file(var.cf_cert_pem_path)
}

resource "aws_vpc" "vpc_main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_subnet" "main" {
  vpc_id = aws_vpc.vpc_main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = var.aws_availability_zone
}

resource "aws_internet_gateway" "inet_gateway" {
  vpc_id = aws_vpc.vpc_main.id
}

resource "aws_route_table" "inet_route" {
  vpc_id = aws_vpc.vpc_main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.inet_gateway.id
  }
}

resource "aws_route_table_association" "external-main" {
  subnet_id = aws_subnet.main.id
  route_table_id = aws_route_table.inet_route.id
}

resource "aws_security_group" "sec_grp_load_balancers" {
  name = "load_balancers"
  description = "Allows all traffic"
  vpc_id = aws_vpc.vpc_main.id

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sec_grp_ecs" {
  name = "ecs"
  description = "Allows all traffic"
  vpc_id = aws_vpc.vpc_main.id

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = [aws_security_group.sec_grp_load_balancers.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "ecs_main" {
  name = var.aws_ecs_cluster_name
}

resource "aws_launch_configuration" "ecs" {
  name = "ECS ${var.aws_ecs_cluster_name}"
  image_id = var.aws_ami_ecs
  instance_type = var.aws_ecs_instance_type
  security_groups = [aws_security_group.sec_grp_ecs.id]
  iam_instance_profile = aws_iam_instance_profile.ecs.name
  associate_public_ip_address = true
  user_data = "#!/bin/bash\necho ECS_CLUSTER='${var.aws_ecs_cluster_name}' > /etc/ecs/ecs.config"
}

resource "aws_autoscaling_group" "ecs-cluster" {
  name = "ECS ${var.aws_ecs_cluster_name}"
  min_size = var.aws_ecs_instance_count
  max_size = var.aws_ecs_instance_count
  desired_capacity = var.aws_ecs_instance_count
  health_check_type = "EC2"
  launch_configuration = aws_launch_configuration.ecs.name
  vpc_zone_identifier = [aws_subnet.main.id]
}

resource "aws_ecs_task_definition" "cloudflared-test" {
  family = "cloudflared-test"
  container_definitions = templatefile("task-definitions/cloudflared.json", {
    aws_cert_pem_secret_arn = aws_secretsmanager_secret.cert_pem.arn,
    cf_hostname = var.cf_hostname,
    cf_origin = var.cf_origin
  })
  execution_role_arn = aws_iam_role.ecs_host_role.arn
}

// Enable if you want to access the metrics server
resource "aws_elb" "cloudflared-elb" {
  name = "elb-cloudflared"
  security_groups = [aws_security_group.sec_grp_load_balancers.id]
  subnets = [aws_subnet.main.id]

  listener {
    lb_protocol = "http"
    lb_port = 32803

    instance_protocol = "http"
    instance_port = 32803
  }

  health_check {
    healthy_threshold = 3
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:32803/metrics"
    interval = 5
  }

  cross_zone_load_balancing = true
}

resource "aws_ecs_service" "cloudflared-test" {
  name = "ecs-cloudflared"
  cluster = aws_ecs_cluster.ecs_main.id
  task_definition = aws_ecs_task_definition.cloudflared-test.arn
  // Enable if you want to access the metrics server
  iam_role = aws_iam_role.ecs_host_role.arn
  desired_count = 1
  depends_on = [aws_iam_role_policy.ecs_role_policy]


  // Enable if you want to access the metrics server
  load_balancer {
    elb_name = aws_elb.cloudflared-elb.id
    container_name = "ecs-cloudflared"
    container_port = 32803
  }
}

resource "aws_iam_role" "ecs_host_role" {
  name = "ecs_host_role"
  assume_role_policy = file("policies/ecs-role.json")
}

resource "aws_iam_role_policy" "ecs_role_policy" {
  name = "ecs_role_policy"
  policy = file("policies/ecs-role-policy.json")
  role = aws_iam_role.ecs_host_role.id
}

resource "aws_iam_instance_profile" "ecs" {
  name = "ecs-instance-profile"
  path = "/"
  role = aws_iam_role.ecs_host_role.name
}