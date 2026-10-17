module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Endpoint público para acesso via kubectl/CI (kubeconfig). Configurável e
  # restringível por CIDR — em produção, limite a IPs da VPN/CI ou use privado.
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # IRSA (OIDC provider) é necessário para o AWS Load Balancer Controller e o
  # External Secrets Operator assumirem roles IAM via service accounts.
  enable_irsa = true

  # Acesso admin ao cluster para o principal que aplica o Terraform (configurável).
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  # Acesso de deploy para as esteiras dos 4 servicos (tc-fase4-<servico>): cada CD
  # roda kubectl no cluster (Etapa 8) sem access keys, via OIDC.
  #
  # Os operadores humanos listados em cluster_admin_principal_arns tambem
  # recebem acesso: sem isso o cluster so e alcancavel pelas esteiras, o que
  # inviabiliza diagnostico e a demonstracao por kubectl.
  access_entries = merge(
    {
      for arn in var.service_deploy_role_arns :
      basename(arn) => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    },
    {
      for arn in var.cluster_admin_principal_arns :
      "operador_${basename(arn)}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    }
  )

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      # AL2023: o Amazon Linux 2 foi descontinuado a partir do EKS 1.33 —
      # sem ami_type explícito o módulo tentaria AL2 e o CreateNodegroup falharia.
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      desired_size   = 3
      min_size       = 2
      max_size       = 5
    }
  }
}

# Providers kubernetes/helm autenticados no cluster recém-criado. O exec plugin
# usa `aws eks get-token`, evitando tokens estáticos que expiram.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

# Provider helm v3: a configuração do cluster passou a ser ATRIBUTO (kubernetes = {})
# em vez de bloco. Exigido pelo módulo de addons (eks-blueprints-addons).
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
