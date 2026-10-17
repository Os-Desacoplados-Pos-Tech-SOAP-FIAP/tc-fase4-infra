output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint do API Server do EKS."
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Comando pronto para configurar o kubeconfig local."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "ecr_repository_urls" {
  description = "URL do repositório ECR de cada serviço (usada pelo CD de cada repo)."
  value       = { for service, repository in aws_ecr_repository.service : service => repository.repository_url }
}

# --- Consumidos pelos repos dos serviços, pela Lambda e pelo gateway via terraform_remote_state ---

output "vpc_id" {
  description = "ID da VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Bloco CIDR da VPC (regras de SG do ALB e do VPC Link)."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "IDs das subnets privadas (RDS dos serviços, Lambda e VPC Link)."
  value       = module.vpc.private_subnets
}

output "node_security_group_id" {
  description = "SG dos nodes do EKS (consumido pelos repos dos serviços para liberar o 5432 no RDS)."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster (IRSA dos serviços e dos addons)."
  value       = module.eks.oidc_provider_arn
}

output "jwt_secret_name" {
  description = "Nome do segredo JWT_SECRET no Secrets Manager."
  value       = aws_secretsmanager_secret.shared["jwt"].name
}

output "jwt_secret_arn" {
  description = "ARN do segredo JWT_SECRET no Secrets Manager."
  value       = aws_secretsmanager_secret.shared["jwt"].arn
}

output "internal_token_secret_name" {
  description = "Nome do segredo INTERNAL_SERVICE_TOKEN no Secrets Manager."
  value       = aws_secretsmanager_secret.shared["internal_token"].name
}

output "internal_token_secret_arn" {
  description = "ARN do segredo INTERNAL_SERVICE_TOKEN no Secrets Manager."
  value       = aws_secretsmanager_secret.shared["internal_token"].arn
}

output "ingress_group_name" {
  description = "Nome do IngressGroup do ALB interno (anotação alb.ingress.kubernetes.io/group.name)."
  value       = local.ingress_group_name
}

output "alb_security_group_id" {
  description = "SG do ALB interno (anotação alb.ingress.kubernetes.io/security-groups dos Ingress)."
  value       = aws_security_group.alb.id
}

# --- API Gateway (URL pública conhecida antes do deploy dos serviços) ---

output "api_id" {
  description = "ID do API Gateway HTTP (consumido pela stack gateway/)."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "URL pública do API Gateway (único ponto de entrada da aplicação)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_execution_arn" {
  description = "Execution ARN do API Gateway (source_arn das permissões das Lambdas)."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "public_base_url" {
  description = "Base pública dos links enviados ao cliente (PUBLIC_BASE_URL do Billing)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "mercadopago_webhook_url" {
  description = "URL de notificação do Mercado Pago (MP_NOTIFICATION_URL do Billing)."
  value       = "${aws_apigatewayv2_api.this.api_endpoint}/api/billing/webhooks/mercadopago?source_news=webhooks"
}
