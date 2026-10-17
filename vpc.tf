data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Até 3 AZs para alta disponibilidade do EKS e do RDS. Usamos min() para não
  # quebrar em regiões com menos de 3 AZs disponíveis.
  azs = slice(
    data.aws_availability_zones.available.names,
    0,
    min(3, length(data.aws_availability_zones.available.names)),
  )
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # Uma subnet pública e uma privada por AZ (6 subnets no total).
  private_subnets = [for k in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, k + 8)]

  # NAT gateway único: econômico para ambiente de estudo/sandbox.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags exigidas pela descoberta de subnets do EKS / AWS Load Balancer Controller.
  # A tag kubernetes.io/cluster/<nome>=shared permite o discovery das subnets pelo
  # cluster e pelo ALB controller (shared = compartilhada, não exclusiva do cluster).
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
