# ---------- cluster + logs ----------

resource "aws_ecs_cluster" "main" {
  name = var.project
}

# all container logs go here (kept 1 day - it's a daily demo)
resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${var.project}"
  retention_in_days = 1
}

# ---------- IAM: lets ECS pull from ECR and write logs ----------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------- service discovery: kafka.shop.local, mongo.shop.local, api.shop.local ----------

resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "shop.local"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "svc" {
  for_each      = toset(["kafka", "mongo", "api"])
  name          = each.key
  force_destroy = true

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

# ---------- shared settings ----------

locals {
  # where each container sends its logs
  log_config = {
    for name in ["kafka", "mongo", "api", "client"] : name => {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.main.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = name
      }
    }
  }

  # our 2 images in ECR, tagged with the code fingerprint from ecr.tf
  api_image    = "${aws_ecr_repository.app["api"].repository_url}:${local.image_tag["api"]}"
  client_image = "${aws_ecr_repository.app["client"].repository_url}:${local.image_tag["client"]}"

  # every task runs in our subnets, behind the tasks firewall
  # public IP only so it can download images (no NAT) - the firewall still blocks all incoming
  subnets = aws_subnet.public[*].id
}

# ---------- kafka ----------

resource "aws_ecs_task_definition" "kafka" {
  family                   = "${var.project}-kafka"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name             = "kafka"
    image            = var.kafka_image
    essential        = true
    portMappings     = [{ containerPort = 9092, protocol = "tcp" }]
    logConfiguration = local.log_config["kafka"]
    environment = [
      # same settings as docker compose, only the address changed to kafka.shop.local
      { name = "KAFKA_NODE_ID", value = "1" },
      { name = "KAFKA_PROCESS_ROLES", value = "broker,controller" },
      { name = "KAFKA_LISTENERS", value = "PLAINTEXT://:9092,CONTROLLER://:9093" },
      { name = "KAFKA_ADVERTISED_LISTENERS", value = "PLAINTEXT://kafka.shop.local:9092" },
      { name = "KAFKA_CONTROLLER_LISTENER_NAMES", value = "CONTROLLER" },
      { name = "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP", value = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT" },
      { name = "KAFKA_CONTROLLER_QUORUM_VOTERS", value = "1@localhost:9093" },
      { name = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR", value = "1" },
      { name = "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR", value = "1" },
      { name = "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR", value = "1" },
      { name = "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS", value = "0" },
    ]
  }])
}

resource "aws_ecs_service" "kafka" {
  name            = "kafka"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.kafka.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # never run 2 kafkas at once during an update
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # NEW: terraform waits until kafka is running (and its name is registered) before moving on
  wait_for_steady_state = true

  network_configuration {
    subnets          = local.subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.svc["kafka"].arn
  }
}

# ---------- mongo ----------

resource "aws_ecs_task_definition" "mongo" {
  family                   = "${var.project}-mongo"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name             = "mongo"
    image            = var.mongo_image
    essential        = true
    portMappings     = [{ containerPort = 27017, protocol = "tcp" }]
    logConfiguration = local.log_config["mongo"]
  }])
}

resource "aws_ecs_service" "mongo" {
  name            = "mongo"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mongo.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # never run 2 databases at once during an update
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # NEW: terraform waits until mongo is running (and its name is registered) before moving on
  wait_for_steady_state = true

  network_configuration {
    subnets          = local.subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.svc["mongo"].arn
  }
}

# ---------- api ----------

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name             = "api"
    image            = local.api_image
    essential        = true
    portMappings     = [{ containerPort = 8000, protocol = "tcp" }]
    logConfiguration = local.log_config["api"]
    environment = [
      { name = "KAFKA", value = "kafka.shop.local:9092" },
      { name = "MONGO", value = "mongodb://mongo.shop.local:27017" },
    ]
  }])

  # the image must be pushed before ECS tries to pull it
  depends_on = [terraform_data.image]
}

resource "aws_ecs_service" "api" {
  name            = "api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.svc["api"].arn
  }

  # NEW: start only after kafka and mongo are up, so their names already exist
  depends_on = [aws_ecs_service.kafka, aws_ecs_service.mongo]
}

# ---------- client (behind the ALB) ----------

resource "aws_ecs_task_definition" "client" {
  family                   = "${var.project}-client"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name             = "client"
    image            = local.client_image
    essential        = true
    portMappings     = [{ containerPort = 8000, protocol = "tcp" }]
    logConfiguration = local.log_config["client"]
    environment = [
      { name = "KAFKA", value = "kafka.shop.local:9092" },
      { name = "API", value = "http://api.shop.local:8000" },
    ]
  }])

  depends_on = [terraform_data.image]
}

resource "aws_ecs_service" "client" {
  name                              = "client"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.client.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = local.subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  # register every client task with the ALB
  load_balancer {
    target_group_arn = aws_lb_target_group.client.arn
    container_name   = "client"
    container_port   = 8000
  }

  # the ALB must be listening before the service attaches to it
  # NEW: and kafka + api must be up first, so their names already exist
  # depends_on = [aws_lb_listener.https]
  depends_on = [aws_lb_listener.https, aws_ecs_service.kafka, aws_ecs_service.api]
}