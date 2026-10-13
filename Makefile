# Automação dos fluxos de desenvolvimento, provisionamento e testes.
# Execute "make help" para listar os comandos.

SHELL := /bin/bash
.DEFAULT_GOAL := help

SERVICES      := Contratos "Flash Sales"
CLUSTER_NAME  ?= devops-api
NAMESPACE     ?= devops-api
TF_DIR        := infra/terraform
KUBECONFIG    ?= $(CURDIR)/$(TF_DIR)/kubeconfig
COMPOSE_URL   ?= http://localhost:8080
K8S_URL       ?= http://localhost:8081
K6_IMAGE      ?= grafana/k6:1.3.0

export KUBECONFIG

.PHONY: help
help: ## Lista os comandos disponíveis
	@awk 'BEGIN {FS = ":.*##"; printf "\nUso: make \033[36m<alvo>\033[0m\n"} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
		/^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Desenvolvimento

.PHONY: install
install: ## Instala as dependências das APIs (npm ci)
	@for s in $(SERVICES); do echo "==> $$s"; (cd "$$s" && npm ci --no-audit --no-fund) || exit 1; done

.PHONY: test
test: ## Executa typecheck e testes unitários das APIs
	@for s in $(SERVICES); do echo "==> $$s"; (cd "$$s" && npm run typecheck && npm test -- --ci) || exit 1; done

.PHONY: build
build: ## Compila as APIs (TypeScript -> dist/)
	@for s in $(SERVICES); do echo "==> $$s"; (cd "$$s" && npm run build) || exit 1; done

##@ Docker Compose (ambiente local completo)

.env:
	cp .env.example .env
	@echo "Arquivo .env criado a partir de .env.example — troque as senhas!"

.PHONY: up
up: .env ## Sobe todo o ambiente (APIs, Postgres, Redis, gateway, Prometheus, Grafana)
	docker compose up -d --build --wait
	./scripts/seed-tickets.sh compose show-2026 1000
	@echo -e "\nGateway:    $(COMPOSE_URL)\nGrafana:    http://localhost:3001\nPrometheus: http://localhost:9090"

.PHONY: down
down: ## Para o ambiente (mantém os volumes)
	docker compose down

.PHONY: clean
clean: ## Para o ambiente e APAGA os volumes (dados)
	docker compose down -v

.PHONY: logs
logs: ## Acompanha os logs de todos os serviços
	docker compose logs -f --tail=100

.PHONY: ps
ps: ## Status dos containers
	docker compose ps

.PHONY: smoke
smoke: ## Smoke test no ambiente Docker Compose
	./scripts/seed-tickets.sh compose smoke-test 10 --force
	./scripts/smoke-test.sh $(COMPOSE_URL)

.PHONY: load-test
load-test: ## Teste de carga do checkout + verificação de overselling (Compose)
	./scripts/seed-tickets.sh compose load-test 500 --force
	docker run --rm -i --network devops-api_edge -v "$(CURDIR)/tests/load:/scripts:ro" \
		-e CHECKOUT_URL=http://flash-sales:3000/checkout -e EVENT_ID=load-test \
		$(K6_IMAGE) run /scripts/flash-sale-spike.js
	./scripts/check-oversell.sh compose load-test 500

.PHONY: bulkhead-test
bulkhead-test: ## Exports pesados x latência do checkout (Compose)
	docker run --rm -i --network devops-api_edge -v "$(CURDIR)/tests/load:/scripts:ro" \
		-e EXPORT_URL=http://flash-sales-export:3000/tickets/export \
		-e CHECKOUT_URL=http://flash-sales:3000/checkout \
		$(K6_IMAGE) run /scripts/export-bulkhead.js

##@ Kubernetes (kind provisionado com Terraform)

.PHONY: k8s-up
k8s-up: ## Provisiona o cluster kind + Traefik + metrics-server (Terraform)
	terraform -chdir=$(TF_DIR) init -input=false
	terraform -chdir=$(TF_DIR) apply -auto-approve -input=false

.PHONY: k8s-images
k8s-images: ## Constrói as imagens e carrega no cluster kind
	docker build -t devops-api/contratos:local Contratos
	docker build -t devops-api/flash-sales:local "Flash Sales"
	kind load docker-image devops-api/contratos:local devops-api/flash-sales:local --name $(CLUSTER_NAME)

.PHONY: k8s-deploy
k8s-deploy: ## Aplica os manifestos (overlay dev + monitoramento) e aguarda o rollout
	kubectl apply -k infra/k8s/overlays/dev
	kubectl apply -k infra/k8s/monitoring
	kubectl -n $(NAMESPACE) rollout status statefulset/postgres --timeout=300s
	kubectl -n $(NAMESPACE) rollout status statefulset/redis --timeout=300s
	@for d in contratos flash-sales flash-sales-export; do \
		kubectl -n $(NAMESPACE) rollout status deployment/$$d --timeout=300s || exit 1; \
	done
	kubectl -n monitoring rollout status deployment/prometheus --timeout=300s
	kubectl -n monitoring rollout status deployment/grafana --timeout=300s

.PHONY: k8s-seed
k8s-seed: ## Cadastra o estoque do evento show-2026 no Redis do cluster
	./scripts/seed-tickets.sh k8s show-2026 1000

.PHONY: k8s-smoke
k8s-smoke: ## Smoke test via ingress do cluster
	./scripts/seed-tickets.sh k8s smoke-test 10 --force
	./scripts/smoke-test.sh $(K8S_URL)

.PHONY: k8s-all
k8s-all: k8s-up k8s-images k8s-deploy k8s-seed k8s-smoke ## Provisiona, implanta e testa tudo no Kubernetes

.PHONY: k8s-status
k8s-status: ## Pods, HPAs e consumo de recursos
	kubectl -n $(NAMESPACE) get pods,hpa,pdb,ingress -o wide
	-kubectl -n $(NAMESPACE) top pods

.PHONY: k8s-load-test
k8s-load-test: ## Carga dentro do cluster (bulkhead + HPA); acompanhe com "make k8s-status"
	-kubectl -n monitoring delete job k6-load-test --ignore-not-found
	kubectl apply -k tests/load
	kubectl -n monitoring wait --for=condition=Ready pod -l app.kubernetes.io/name=k6-load-test --timeout=120s
	kubectl -n monitoring logs -f job/k6-load-test

.PHONY: k8s-grafana
k8s-grafana: ## Abre o Grafana do cluster em http://localhost:3002 (admin / dev-grafana)
	kubectl -n monitoring port-forward svc/grafana 3002:3000

.PHONY: k8s-prometheus
k8s-prometheus: ## Abre o Prometheus do cluster em http://localhost:9091
	kubectl -n monitoring port-forward svc/prometheus 9091:9090

.PHONY: k8s-down
k8s-down: ## Destrói o cluster (Terraform destroy)
	terraform -chdir=$(TF_DIR) destroy -auto-approve -input=false

##@ Qualidade da infraestrutura

.PHONY: lint
lint: ## Valida Dockerfiles, scripts, Compose, manifestos e Terraform (via containers)
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.config/hadolint.yaml:ro" hadolint/hadolint:v2.14.0 < Contratos/Dockerfile
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.config/hadolint.yaml:ro" hadolint/hadolint:v2.14.0 < "Flash Sales/Dockerfile"
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt koalaman/shellcheck:v0.11.0 scripts/*.sh infra/k8s/base/postgres/init-databases.sh
	docker compose --env-file .env.example config --quiet
	@for t in infra/k8s/overlays/dev infra/k8s/monitoring tests/load; do \
		echo "==> $$t"; \
		kubectl kustomize $$t | docker run --rm -i ghcr.io/yannh/kubeconform:v0.7.0 -strict -summary \
			-schema-location default \
			-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' || exit 1; \
	done
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	terraform -chdir=$(TF_DIR) init -backend=false -input=false > /dev/null
	terraform -chdir=$(TF_DIR) validate
