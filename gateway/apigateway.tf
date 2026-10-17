# Integrações, rotas, authorizer e VPC Link do API Gateway HTTP. A API e o stage
# `$default` (auto_deploy) são da stack raiz (apigateway.tf), para que a URL pública
# exista antes do deploy dos serviços; aqui só são lidos `api_id` e `api_execution_arn`.

# --- /auth -> Lambda de autenticação por CPF ---

resource "aws_apigatewayv2_integration" "auth_lambda" {
  api_id                 = local.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = data.terraform_remote_state.auth.outputs.auth_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = local.api_id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_lambda_permission" "auth" {
  statement_id  = "AllowApiGatewayAuth"
  action        = "lambda:InvokeFunction"
  function_name = data.terraform_remote_state.auth.outputs.auth_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.api_execution_arn}/*/*"
}

# --- Authorizer (JWT do cliente, perfil CLIENTE) ---

resource "aws_apigatewayv2_authorizer" "cliente" {
  api_id                            = local.api_id
  authorizer_type                   = "REQUEST"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "cliente-jwt"
  authorizer_uri                    = data.terraform_remote_state.auth.outputs.authorizer_invoke_arn
  authorizer_result_ttl_in_seconds  = 300
}

resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowApiGatewayAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = data.terraform_remote_state.auth.outputs.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.api_execution_arn}/authorizers/${aws_apigatewayv2_authorizer.cliente.id}"
}

# --- Rede privada: VPC Link -> ALB interno ---
#
# O ALB é interno (scheme internal): o gateway só o alcança por um VPC Link (v2)
# com ENIs nas subnets privadas. O SG do VPC Link só sai na porta 80 para a VPC, e o
# SG do ALB (gerenciado na stack raiz) aceita a porta 80 a partir dele.

resource "aws_security_group" "vpc_link" {
  name        = "${var.project_name}-vpc-link"
  description = "ENIs do VPC Link do API Gateway"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project_name}-vpc-link"
  }
}

resource "aws_vpc_security_group_egress_rule" "vpc_link_http" {
  security_group_id = aws_security_group.vpc_link.id
  description       = "HTTP para o ALB interno"
  cidr_ipv4         = local.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_vpc_link" {
  security_group_id            = local.alb_security_group_id
  description                  = "HTTP a partir do VPC Link do API Gateway"
  referenced_security_group_id = aws_security_group.vpc_link.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.project_name}-vpc-link"
  subnet_ids         = local.private_subnets
  security_group_ids = [aws_security_group.vpc_link.id]
}

# Uma única integração privada no listener HTTP do ALB. Em integração privada o
# API Gateway repassa o caminho original da requisição (não há URI com {proxy} como
# na Fase 3, que usava HTTP_PROXY público e precisava de duas integrações). O
# overwrite:path = $request.path deixa isso explícito e evita que um stage nomeado
# prefixe o caminho (a doc da AWS indica esse mapeamento para remover o stage).
resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = local.api_id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.this.id
  integration_uri        = data.aws_lb_listener.http.arn
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

# --- Rotas para o ALB ---

# Área do cliente no OS: exige o JWT de cliente emitido pela Lambda (authorizer).
resource "aws_apigatewayv2_route" "os_publico" {
  api_id             = local.api_id
  route_key          = "ANY /api/os/publico/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.cliente.id
}

# Rota interna do OS (usada só pela Lambda, que chama o ALB direto pela VPC):
# AWS_IAM exige assinatura SigV4, então quem vem de fora recebe 403.
resource "aws_apigatewayv2_route" "os_internal" {
  api_id             = local.api_id
  route_key          = "ANY /api/os/internal/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "AWS_IAM"
}

# Demais rotas: proxy direto, cada serviço valida o JWT de funcionário. Inclui
# /api/billing/publico/* (link do e-mail, token na query) e /api/billing/webhooks/*
# (assinatura do Mercado Pago), que não passam por authorizer.
resource "aws_apigatewayv2_route" "catch_all" {
  api_id    = local.api_id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}
