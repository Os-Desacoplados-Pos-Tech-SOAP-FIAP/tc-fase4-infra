# Stack separada do cluster: o gateway referencia o ALB interno, que só existe
# DEPOIS do deploy dos serviços (o AWS Load Balancer Controller cria o ALB a partir
# dos Ingress do IngressGroup), e a Lambda de auth, que também depende do ALB.
# Por isso o apply desta stack é o ÚLTIMO da ordem de subida (spec §6.6):
#   infra -> terraform dos serviços -> CD dos serviços (ALB) -> auth -> gateway.
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "infra/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "auth" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "auth/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  vpc_id                = data.terraform_remote_state.infra.outputs.vpc_id
  vpc_cidr              = data.terraform_remote_state.infra.outputs.vpc_cidr
  private_subnets       = data.terraform_remote_state.infra.outputs.private_subnets
  cluster_name          = data.terraform_remote_state.infra.outputs.cluster_name
  ingress_group_name    = data.terraform_remote_state.infra.outputs.ingress_group_name
  alb_security_group_id = data.terraform_remote_state.infra.outputs.alb_security_group_id
}

# ALB interno único criado pelo IngressGroup `oficina-fase4` (Ingress dos 4 serviços).
# Para IngressGroup explícito, o controller usa o nome do grupo na tag ingress.k8s.aws/stack.
data "aws_lb" "app" {
  tags = {
    "elbv2.k8s.aws/cluster" = local.cluster_name
    "ingress.k8s.aws/stack" = local.ingress_group_name
  }
}

data "aws_lb_listener" "http" {
  load_balancer_arn = data.aws_lb.app.arn
  port              = 80
}
