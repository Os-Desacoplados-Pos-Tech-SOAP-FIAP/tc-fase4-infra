# Observabilidade — Grafana Cloud, dashboard e alertas

Guia para ligar a telemetria da Fase 4 no Grafana Cloud, importar o dashboard **Saga da OS**
(`saga-da-os.json`, nesta pasta), criar os alertas e rastrear uma OS do começo ao fim.

O código já está pronto nos 4 serviços (OpenTelemetry: traces, métricas da saga e da
mensageria, logs JSON do pino com `trace_id`/`span_id`) e o Terraform já tem o Grafana Alloy
(`observability.tf`). Falta só **cadastrar as credenciais**: sem elas o Alloy não é instalado
(`count = 0`) e os serviços sobem sem exportar telemetria.

## 1. O que o Alloy coleta

O chart `k8s-monitoring` (2.0.46) instala o Alloy em três papéis, todos enviando para o
gateway OTLP do Grafana Cloud (HTTP, basic auth):

| Papel | O que coleta | Vai para |
|---|---|---|
| `alloy-receiver` | OTLP/HTTP na porta 4318 (`grafana-k8s-monitoring-alloy-receiver.observability.svc.cluster.local`): traces e métricas dos 4 serviços | Tempo e Prometheus (Mimir) |
| `alloy-logs` | stdout/stderr de todos os pods do cluster (`podLogs`), incluindo os logs JSON do pino | Loki |
| `alloy-metrics` | métricas do cluster (`clusterMetrics`: CPU/memória de pods e nodes, kube-state-metrics) | Prometheus (Mimir) |

O CD de cada serviço só injeta `OTEL_EXPORTER_OTLP_ENDPOINT` no ConfigMap se o Service do
receiver existir no namespace `observability`. **Se os serviços foram implantados antes do
Alloy, rode o CD deles de novo** (ou `kubectl rollout restart deployment -n <os|catalog|billing|execution>`
depois de recriar o ConfigMap) para que passem a exportar.

Os logs **não** vão por OTLP: os serviços só escrevem JSON no stdout e o `alloy-logs` lê do
node. Por isso, no compose local (seção 5), o Loki fica vazio.

## 2. Credenciais (reaproveitando o stack da Fase 3)

O stack do Grafana Cloud da Fase 3 continua valendo; não é preciso criar outro. O Instance ID e
o endpoint OTLP são os mesmos. Gere um token novo para a Fase 4:

1. No **Grafana Cloud Portal** (grafana.com → *My Account*), abra o stack e clique em
   **OpenTelemetry → Configure**. A tela mostra o **OTLP Endpoint**
   (`https://otlp-gateway-prod-<regiao>.grafana.net/otlp`) e o **Instance ID** (número).
2. Em **Security → Access Policies → Create access policy**:
   - nome: `tc-fase4-alloy`; realm: o stack da Fase 3;
   - scopes: `metrics:write`, `logs:write`, `traces:write`;
   - **Create**, depois **Add token** (nome `tc-fase4-infra`). O token começa com `glc_` e
     aparece uma única vez.
3. Cadastre os três secrets no repositório da infra (o `gh` pede o valor no terminal, sem
   deixar rastro no histórico do shell):

```bash
gh secret set GRAFANA_CLOUD_OTLP_ENDPOINT -R Os-Desacoplados-Pos-Tech-SOAP-FIAP/tc-fase4-infra   # https://otlp-gateway-prod-<regiao>.grafana.net/otlp
gh secret set GRAFANA_CLOUD_INSTANCE_ID   -R Os-Desacoplados-Pos-Tech-SOAP-FIAP/tc-fase4-infra   # <instance-id>
gh secret set GRAFANA_CLOUD_TOKEN         -R Os-Desacoplados-Pos-Tech-SOAP-FIAP/tc-fase4-infra   # glc_<token>

gh secret list -R Os-Desacoplados-Pos-Tech-SOAP-FIAP/tc-fase4-infra
```

O workflow `Terraform` repassa esses secrets como `TF_VAR_grafana_cloud_otlp_endpoint`,
`TF_VAR_grafana_cloud_instance_id` e `TF_VAR_grafana_cloud_token`.

4. **Actions → Terraform → Run workflow → `apply`** e aprove em *Review deployments*. Depois:

```bash
aws eks update-kubeconfig --name oficina-fase4 --region us-east-1
kubectl get pods -n observability   # alloy-metrics, alloy-logs e alloy-receiver em Running
```

5. Gere tráfego (uma OS de ponta a ponta) e confira no **Explore**:

| Fonte | Consulta | Esperado |
|---|---|---|
| Prometheus | `saga_iniciadas_total` | contador com `job="tc-fase4-os"` |
| Prometheus | `mensagens_processadas_total` | uma série por `job`, `tipo` e `resultado` |
| Tempo | `{ resource.service.name = "tc-fase4-os" }` | traces com spans dos 4 serviços |
| Loki | `{namespace="os"} \| json` | logs JSON com `trace_id` |

## 3. Importar o dashboard

O mesmo JSON serve no Grafana Cloud e no compose local: as fontes de dados são variáveis do
tipo *datasource* (`DS_PROMETHEUS`, `DS_TEMPO`), sem `__inputs`. Cada uma assume a primeira
fonte do tipo e pode ser trocada no topo do dashboard.

**Pela interface:** **Dashboards → New → Import**, cole o conteúdo de `saga-da-os.json` (ou
faça upload do arquivo) → **Load** → escolha a pasta → **Import**. Depois, no topo do dashboard,
confira se *Prometheus* aponta para `grafanacloud-<stack>-prom` e *Tempo* para
`grafanacloud-<stack>-traces`.

**Pela API** (token de *service account* com papel Editor, criado em **Administration →
Users and access → Service accounts**):

```bash
GRAFANA_URL=https://<stack>.grafana.net
GRAFANA_SA_TOKEN=glsa_<token>
jq '{dashboard: (. + {id: null}), overwrite: true, folderUid: ""}' observability/saga-da-os.json |
  curl -sS -X POST "$GRAFANA_URL/api/dashboards/db" \
    -H "Authorization: Bearer $GRAFANA_SA_TOKEN" -H 'Content-Type: application/json' -d @-
```

O `uid` é fixo (`saga-da-os`): reimportar sobrescreve o mesmo dashboard. Se ajustar painéis
no Grafana, exporte de volta (**Share → Export → Save to file**) e atualize o arquivo aqui.

### Painéis

| Painel | Tipo | Consulta |
|---|---|---|
| Sagas iniciadas / concluídas / compensadas | Stat | `sum(increase(saga_iniciadas_total[$__range])) or vector(0)` (idem `saga_concluidas_total`, `saga_compensacoes_total`) |
| DLQ por serviço | Stat (vermelho se > 0) | `max by (job) (dlq_mensagens) or max by (job) (target_info{job=~"tc-fase4-.*"}) * 0` |
| Funil da saga | Time series | `sum(increase(saga_iniciadas_total[$__rate_interval]))` (idem concluídas e compensadas) |
| Compensações por motivo | Barras | `sum by (motivo) (increase(saga_compensacoes_total[$__range]))` |
| Duração média por etapa | Barras | `sum by (etapa) (increase(saga_duracao_etapa_segundos_sum[$__range])) / sum by (etapa) (increase(saga_duracao_etapa_segundos_count[$__range]))` |
| OS por status | Barras | `max by (status) (os_por_status)` |
| Mensagens processadas por serviço | Time series | `sum by (job, resultado) (increase(mensagens_processadas_total[$__rate_interval]))` |
| Outbox pendente por serviço | Time series | `max by (job) (outbox_pendentes) or max by (job) (target_info{job=~"tc-fase4-.*"}) * 0` |
| HTTP: taxa de erro 5xx | Time series | `(sum by (job) (rate(http_server_request_duration_seconds_count{job=~"tc-fase4-.*", http_response_status_code=~"5.."}[$__rate_interval])) or sum by (job) (rate(http_server_request_duration_seconds_count{job=~"tc-fase4-.*"}[$__rate_interval])) * 0) / sum by (job) (rate(http_server_request_duration_seconds_count{job=~"tc-fase4-.*"}[$__rate_interval]))` |
| HTTP: latência p95 | Time series | `histogram_quantile(0.95, sum by (job, le) (rate(http_server_request_duration_seconds_bucket{job=~"tc-fase4-.*"}[$__rate_interval])))` |
| Traces recentes do OS | Tabela (Tempo) | `{ resource.service.name = "tc-fase4-os" }` |
| Traces da OS selecionada | Tabela (Tempo) | `{ span.oficina.os_id = "$os_id" }` (variável **OS (id)** no topo) |

Notas sobre as consultas:

- `job` é o `service.name` de cada serviço (`tc-fase4-os`, `tc-fase4-catalog`,
  `tc-fase4-billing`, `tc-fase4-execution`).
- Os painéis de saga usam `increase(...[$__range])`: com o pouco tráfego de um teste, uma
  taxa por segundo ficaria perto de zero. Para ver um período maior, aumente o intervalo do
  dashboard.
- O `target_info{...} * 0` faz cada serviço que exporta telemetria aparecer com `0` em vez de
  sumir do painel quando o gauge ainda não tem ponto. Os gauges usam `max by (job)` porque um
  pod reiniciado deixa a série antiga viva por alguns minutos (cada processo tem o próprio
  `service.instance.id`) e um `sum` contaria em dobro.
- O `increase` não conta o primeiro incremento de uma série nova (o SDK só exporta o
  contador depois do primeiro `add`, e o Prometheus não tem ponto anterior para comparar).
  Logo depois de subir os serviços, a primeira OS pode não aparecer no funil.

## 4. Alertas

Crie as três regras em **Alerting → Alert rules → New alert rule**:

1. **Nome** da regra (tabela abaixo).
2. **Define query and alert condition**: fonte `grafanacloud-<stack>-prom`, modo **Code**,
   cole a consulta. Em *Expressions*, deixe **Reduce** (*Last*) e **Threshold** com
   *Is above* e o limite da tabela.
3. **Folder** `Oficina`, **Evaluation group** `saga-fase4` com intervalo de **1m**.
4. **Pending period** conforme a tabela.
5. Em *Configure no data and error handling*, **Alert state if no data = Normal** (serviço
   sem DLQ configurada ou sem tráfego HTTP não é falha).
6. Label `severity` e um resumo, por exemplo `{{ $labels.job }}: DLQ com {{ $values.B }} mensagens`.
7. **Contact point**: o e-mail padrão do stack (confira em **Alerting → Contact points**).

Cada consulta agrupa por `job`, então o alerta dispara uma instância por serviço.

| Regra | Consulta (PromQL) | Threshold | Pending | Severity |
|---|---|---|---|---|
| **DLQ com mensagens** | `max by (job) (dlq_mensagens)` | > 0 | 1m | critical |
| **Outbox parada** | `max by (job) (outbox_pendentes)` | > 0 | 5m | warning |
| **Erro HTTP 5xx > 5%** | `sum by (job) (rate(http_server_request_duration_seconds_count{job=~"tc-fase4-.*", http_response_status_code=~"5.."}[5m])) / sum by (job) (rate(http_server_request_duration_seconds_count{job=~"tc-fase4-.*"}[5m]))` | > 0.05 | 0s (a janela de 5 min já está na consulta) | critical |

Mensagem na DLQ significa que o consumidor desistiu dela depois das retentativas: a saga
daquela OS está parada até alguém reprocessar. Outbox pendente por 5 minutos significa que o
publicador não está conseguindo publicar no SNS (os eventos ficam no banco, nada se perde,
mas a saga não anda).

## 5. Local (compose do tc-fase4-os)

O `local/docker-compose.yml` do `tc-fase4-os` sobe o `grafana/otel-lgtm:0.37.0` em
**http://localhost:3005** (`admin` / `admin`) e provisiona os dashboards da pasta montada em
`/otel-lgtm/dashboards/oficina` (provider `local/grafana/dashboards.yaml`, pasta *Oficina*).
Com essa pasta apontando para `../../tc-fase4-infra/observability`, o **Saga da OS** já
aparece em **Dashboards → Oficina**, com as variáveis de datasource resolvidas para o
Prometheus e o Tempo da imagem. O `local/smoke.mjs` gera uma OS de ponta a ponta.

Diferenças em relação ao Cloud: não há métricas do cluster nem logs no Loki (os serviços não
exportam logs por OTLP; use `docker compose logs <servico>` e copie o `trace_id`).

## 6. Rastrear uma OS

**Por que não há um trace único por OS.** Cada ação humana é uma requisição nova: o
funcionário abre a OS, o mecânico conclui o diagnóstico, o cliente aprova o orçamento, o
Mercado Pago confirma o pagamento. Cada uma gera o próprio trace, e dentro dele a ação
atravessa os 4 serviços (o contexto segue nas mensagens SNS/SQS). Entre uma ação e outra
podem passar horas ou dias, então um trace só não faria sentido. O que junta a vida da OS é o
atributo de span **`oficina.os_id`**, gravado nos spans de mensageria.

**No Tempo** (Explore → Tempo → TraceQL):

```traceql
{ span.oficina.os_id = "<id-da-os>" }
```

O resultado lista todos os traces da OS em ordem de tempo: abertura, diagnóstico, orçamento,
reserva, execução, cobrança. No dashboard, preencha a variável **OS (id)** e veja o painel
*Traces da OS selecionada*.

**Do log para o trace.** Os logs do pino têm `trace_id` e `span_id`. No Loki:

```logql
{namespace="os"} | json | trace_id="<trace-id>"
```

Para achar o `trace_id` a partir de uma OS, filtre o texto do id
(`{namespace=~"os|catalog|billing|execution"} |= "<id-da-os>" | json`) e copie o `trace_id`
da linha; depois abra no Tempo (Explore → Tempo → *TraceQL* → cole o id). Se o label
`namespace` não aparecer no seu stack, use o *Label browser* do Loki (com OTLP ele pode vir
como `k8s_namespace_name` ou `service_name`).

Para ter o link direto do log para o trace, configure em **Connections → Data sources →
grafanacloud-<stack>-logs → Derived fields**: nome `TraceID`, regex `"trace_id":"(\w+)"`,
*Internal link* para a fonte Tempo com a consulta `${__value.raw}`.
