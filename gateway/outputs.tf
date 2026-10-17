# A API é criada na stack raiz; estes outputs só repassam os dela, por conveniência.

output "api_endpoint" {
  description = "URL pública do API Gateway (repasse do output da stack raiz)."
  value       = data.terraform_remote_state.infra.outputs.api_endpoint
}

output "public_base_url" {
  description = "Base pública dos links enviados ao cliente (repasse do output da stack raiz)."
  value       = data.terraform_remote_state.infra.outputs.public_base_url
}

output "mercadopago_webhook_url" {
  description = "URL de notificação do Mercado Pago (repasse do output da stack raiz)."
  value       = data.terraform_remote_state.infra.outputs.mercadopago_webhook_url
}
