# API Gateway HTTP: única entrada pública da aplicação.
#
# A API e o stage ficam na stack raiz para que a URL pública exista já no primeiro
# apply da infra, ANTES do deploy dos serviços: o Billing usa essa URL no link do
# e-mail (PUBLIC_BASE_URL) e no webhook do Mercado Pago (MP_NOTIFICATION_URL).
#
# Integrações, rotas, authorizer e VPC Link ficam na stack `gateway/`, que lê
# `api_id` e `api_execution_arn` daqui e só sobe depois do ALB e da Lambda de auth.
# Com auto_deploy, o stage publica sozinho as rotas criadas pela stack `gateway/`.
resource "aws_apigatewayv2_api" "this" {
  name          = "${var.cluster_name}-gateway"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}
