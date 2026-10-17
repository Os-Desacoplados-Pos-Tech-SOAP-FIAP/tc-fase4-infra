# Addons do cluster via blueprints (IRSA + helm gerenciados pelo módulo).
# O AWS Load Balancer Controller junta os Ingress dos 4 servicos (IngressGroup
# `oficina-fase4`) em um unico ALB interno - pre-requisito da Lambda de auth e da
# stack `gateway/`, que referenciam esse ALB. Nenhum Ingress e criado aqui: cada
# servico publica o seu no CD (ver contrato em alb.tf).
module "addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true

  aws_load_balancer_controller = {
    set = [
      # Cluster pequeno (3 nodes): uma réplica basta e sobe mais rápido.
      {
        name  = "replicaCount"
        value = "1"
      },
    ]
  }
}
