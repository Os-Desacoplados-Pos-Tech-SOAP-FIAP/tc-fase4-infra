output "api_endpoint" {
  description = "URL pública do API Gateway (único ponto de entrada da aplicação)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "public_base_url" {
  description = "Base pública dos links enviados ao cliente (ex.: link do orçamento no e-mail)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "webhook_url" {
  description = "URL de notificação do Mercado Pago (MP_NOTIFICATION_URL do Billing na Etapa 8)."
  value       = "${aws_apigatewayv2_api.this.api_endpoint}/api/billing/webhooks/mercadopago?source_news=webhooks"
}
