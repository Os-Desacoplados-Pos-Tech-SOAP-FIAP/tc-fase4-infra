variable "aws_region" {
  description = "Região AWS onde a stack é provisionada."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente lógico (usado em tags e nomes)."
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Nome do cluster EKS e prefixo dos recursos relacionados."
  type        = string
  default     = "oficina-fase4"
}

variable "cluster_version" {
  description = "Versão do Kubernetes do cluster EKS (usar versão em standard support — conferir com `aws eks describe-cluster-versions`)."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC dedicada."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_endpoint_public_access" {
  description = "Expõe o endpoint do API Server do EKS na internet."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público do API Server."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Concede admin do cluster ao principal que aplica o Terraform."
  type        = bool
  default     = true
}

variable "service_deploy_role_arns" {
  description = "Roles OIDC das esteiras dos 4 servicos (tc-fase4-{os,catalog,billing,execution}) que recebem acesso de deploy ao cluster (CD aplica os manifests)."
  type        = list(string)
  default = [
    "arn:aws:iam::538880133939:role/gha-tc-fase4-os",
    "arn:aws:iam::538880133939:role/gha-tc-fase4-catalog",
    "arn:aws:iam::538880133939:role/gha-tc-fase4-billing",
    "arn:aws:iam::538880133939:role/gha-tc-fase4-execution",
  ]
}

variable "cluster_admin_principal_arns" {
  description = "Usuarios/roles IAM que recebem acesso administrativo ao cluster para operacao manual via kubectl (diagnostico e demonstracao)."
  type        = list(string)
  default     = ["arn:aws:iam::538880133939:user/hailton"]
}

variable "ecr_image_tag_mutability" {
  description = "Mutabilidade das tags do ECR. IMMUTABLE (recomendado p/ CI/CD) evita sobrescrever tags."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability deve ser IMMUTABLE ou MUTABLE."
  }
}

# --- Grafana Cloud (observabilidade) ---
# Preenchidas pela esteira a partir dos secrets do repositório. Vazias = observabilidade desligada.

variable "grafana_cloud_otlp_endpoint" {
  description = "Endpoint OTLP do Grafana Cloud (https://otlp-gateway-<regiao>.grafana.net/otlp)."
  type        = string
  default     = ""
}

variable "grafana_cloud_instance_id" {
  description = "Instance ID do stack Grafana Cloud (usuário do basic auth)."
  type        = string
  default     = ""
}

variable "grafana_cloud_token" {
  description = "Token de escrita do Grafana Cloud."
  type        = string
  sensitive   = true
  default     = ""
}
