data "aws_availability_zones" "available_zones" {
  state = "available"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_vpc" "aws_ecs_vpc" {
  cidr_block = "10.32.0.0/16"
  tags = {
    Name = "ecs_go_vpc"
  }
}


resource "aws_subnet" "public" {
  count                   = 2
  cidr_block              = cidrsubnet(aws_vpc.aws_ecs_vpc.cidr_block, 8, 2 + count.index)
  availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.aws_ecs_vpc.id
  map_public_ip_on_launch = true
  tags = {
    Name = "go-public-sub-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = cidrsubnet(aws_vpc.aws_ecs_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.aws_ecs_vpc.id
  tags = {
    Name = "go-private-sub-${count.index}"
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.aws_ecs_vpc.id
  tags = {
    Name = "go-internet-gateway"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.aws_ecs_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gateway.id
}

resource "aws_eip" "gateway" {
  count = 2
  #vpc        = true
  depends_on = [aws_internet_gateway.gateway]
  tags = {
    Name = "go-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "gateway" {
  count         = 2
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.gateway.*.id, count.index)
  tags = {
    Name = "go-nat-${count.index}"
  }
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.aws_ecs_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.gateway.*.id, count.index)
  }
  tags = {
    Name = "go-private-rt-${count.index}"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_security_group" "lb" {
  name   = "this-alb-security-group"
  vpc_id = aws_vpc.aws_ecs_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "default" {
  name            = "this-lb"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.lb.id]
}

resource "aws_lb_target_group" "go_web_app" {
  name        = "this-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.aws_ecs_vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "go_web_app" {
  load_balancer_arn = aws_lb.default.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.go_web_app.id
    type             = "forward"
  }
}

resource "aws_ecr_repository" "go_web_app_repo" {
  name = "go-web-app-repo"
  tags = {
    Name = "latest-go-app"
  }
}

resource "aws_ecs_task_definition" "go_web_app" {
  family                   = "go-web-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn


  # 558855373261.dkr.ecr.us-east-1.amazonaws.com/ecr-ex-terraform:latest
  # registry.gitlab.com/architect-io/artifacts/nodejs-hello-world:latest
  container_definitions = <<DEFINITION
[
  {
    "image": "${aws_ecr_repository.go_web_app_repo.repository_url}",
    "cpu": 1024,
    "memory": 2048,
    "name": "go-web-app",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 3000,
        "hostPort": 3000
      }
    ]
  }
]
DEFINITION
}

resource "aws_security_group" "go_web_app_task" {
  name   = "this-task-security-group"
  vpc_id = aws_vpc.aws_ecs_vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = 3000
    to_port         = 3000
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "main" {
  name = "ecs-cluster"
}

resource "aws_ecs_service" "go_web_app" {
  name            = "go-web-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.go_web_app.arn
  desired_count   = var.app_count
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [aws_security_group.go_web_app_task.id]
    subnets         = aws_subnet.private.*.id
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.go_web_app.id
    container_name   = "go-web-app"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.go_web_app]
}


resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}
