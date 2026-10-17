# Coleta de telemetria do cluster e da aplicação, encaminhada ao Grafana Cloud.
#
# O chart k8s-monitoring instala o Grafana Alloy em três papéis: métricas do
# cluster (CPU/memória dos pods), logs dos containers e um receiver OTLP que a
# API NestJS usa para enviar traces e métricas de negócio.
#
# Enquanto as credenciais do Grafana Cloud não estiverem cadastradas como secrets
# do repositório, o recurso não é criado (count = 0) — assim o apply da infra
# continua funcionando sem observabilidade.
locals {
  observabilidade_habilitada = var.grafana_cloud_otlp_endpoint != "" && var.grafana_cloud_token != ""
}

resource "helm_release" "k8s_monitoring" {
  count = local.observabilidade_habilitada ? 1 : 0

  name       = "grafana-k8s-monitoring"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "k8s-monitoring"
  # Versao exata, nao range: o provider helm v3 recusa o apply quando a versao
  # resolvida no plan difere da constraint escrita aqui.
  version          = "2.0.46"
  namespace        = "observability"
  create_namespace = true

  values = [yamlencode({
    cluster = { name = var.cluster_name }

    destinations = [{
      name = "grafana-cloud-otlp"
      type = "otlp"
      url  = var.grafana_cloud_otlp_endpoint
      # O gateway OTLP do Grafana Cloud so aceita HTTP; o padrao do chart e gRPC.
      protocol = "http"
      auth = {
        type     = "basic"
        username = var.grafana_cloud_instance_id
        password = var.grafana_cloud_token
      }
      metrics = { enabled = true }
      logs    = { enabled = true }
      traces  = { enabled = true }
    }]

    clusterMetrics = { enabled = true }
    podLogs        = { enabled = true }

    # Receiver OTLP usado pela API (OTEL_EXPORTER_OTLP_ENDPOINT no ConfigMap).
    applicationObservability = {
      enabled = true
      receivers = {
        otlp = {
          http = {
            enabled = true
            port    = 4318
          }
        }
      }
    }

    alloy-metrics = { enabled = true }
    alloy-logs    = { enabled = true }

    # O receiver so aceita OTLP se a porta estiver declarada aqui tambem: o chart
    # valida que cada receiver habilitado tem a porta correspondente exposta.
    alloy-receiver = {
      enabled = true
      alloy = {
        extraPorts = [{
          name       = "otlp-http"
          port       = 4318
          targetPort = 4318
          protocol   = "TCP"
        }]
      }
    }
  })]

  depends_on = [module.eks]
}
