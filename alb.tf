# Security group do ALB interno, gerenciado aqui e não pelo AWS Load Balancer
# Controller, para que outras stacks liberem tráfego de forma declarativa:
#   - tc-fase4-auth: Lambda (na VPC) -> ALB na porta 80
#   - gateway/:      VPC Link do API Gateway -> ALB na porta 80
#
# Contrato com os Ingress dos serviços (Etapa 8):
#   alb.ingress.kubernetes.io/scheme: internal
#   alb.ingress.kubernetes.io/group.name: oficina-fase4
#   alb.ingress.kubernetes.io/security-groups: <alb_security_group_id>
#   alb.ingress.kubernetes.io/manage-backend-security-group-rules: "true"
#
# As regras são recursos separados (e não blocos inline) porque as outras stacks
# adicionam regras neste mesmo SG; com blocos inline o Terraform removeria essas
# regras a cada apply.
locals {
  ingress_group_name = "oficina-fase4"
}

resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb"
  description = "ALB interno do IngressGroup ${local.ingress_group_name}"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.cluster_name}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_vpc" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP a partir da VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Saida para os targets (pods)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
