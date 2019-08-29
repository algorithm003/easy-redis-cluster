# -----------------------------------------------------------------
#  Makefile for redis cluster
# -----------------------------------------------------------------

ifneq (${MAKECMDGOALS}, )

# = Git Env =

GIT_CURR_BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)

# = Image Names =

REDIS_NODE_IMAGE = redis:5.0.5-stretch
WEBHOOK_IMAGE = "lizhaochao\\/python-webhook:v0.5"
# python:3.7.4-alpine
# "lizhaochao\\/python-webhook:v0.2"
SCALER_IMAGE := ${REDIS_NODE_IMAGE}

# = Ports =

REDIS_NODE_CLIENT_PORT = 6379
REDIS_NODE_GOSSIP_PORT := $(shell expr $(REDIS_NODE_CLIENT_PORT) + 10000)
WEBHOOK_PORT = 443

# = Common Vars =

APP_NAME = redis-cluster

ENV_DEV = dev
ENV_PRD = prd
NAMESPACE_DEV := ${APP_NAME}-${ENV_DEV}
NAMESPACE_PRD := ${APP_NAME}-${ENV_PRD}

# ===Redis Cluster Base Control===
REDIS_CLUSTER_MIN_POD_REPLICAS = 6
# redis cluster required 6 at least, NOT this redis cluster instance.
# ================================

# = Redis Node Vars =

ifeq (${GIT_CURR_BRANCH}, prd)
	ENV := ${ENV_PRD}
	NAMESPACE := ${NAMESPACE_PRD}
	REDIS_NODE_LIMITS_MEMORY = 7168
	REDIS_NODE_MIN_POD_REPLICAS = $(shell expr $(REDIS_CLUSTER_MIN_POD_REPLICAS) + 5)
	REDIS_NODE_MAX_POD_REPLICAS := $(shell expr $(REDIS_NODE_MIN_POD_REPLICAS) + 6)
	WEBHOOK_POD_REPLICAS = 2
	SCALER_POD_REPLICAS = 2
else
	ENV := ${ENV_DEV}
	NAMESPACE := ${NAMESPACE_DEV}
	REDIS_NODE_LIMITS_MEMORY = 60
	REDIS_NODE_MIN_POD_REPLICAS = $(shell expr $(REDIS_CLUSTER_MIN_POD_REPLICAS) + 0)
	REDIS_NODE_MAX_POD_REPLICAS := $(shell expr $(REDIS_NODE_MIN_POD_REPLICAS) + 2)
	WEBHOOK_POD_REPLICAS = 1
	SCALER_POD_REPLICAS = 1
endif

REDIS_NODE_REQUESTS_MEMORY := ${REDIS_NODE_LIMITS_MEMORY}
REDIS_NODE_MAXMEMORY := $(shell expr $(REDIS_NODE_REQUESTS_MEMORY) \* 2 / 5)
REDIS_NODE_AVERAGE_VALUE := $(shell expr $(REDIS_NODE_MAXMEMORY) \* 4 / 5)
REDIS_NODE_STORAGE := $(shell expr $(REDIS_NODE_LIMITS_MEMORY) \* 2)

REDIS_NODE = redis-node
REDIS_NODE_LABEL := ${REDIS_NODE}
REDIS_NODE_NAME := ${REDIS_NODE}

REDIS_NODE_SERVICE := ${REDIS_NODE}-svc
REDIS_NODE_HPA_NAME := ${REDIS_NODE}-hpa

REDIS_NODE_READINESS_FILENAME := ${REDIS_NODE}-readiness
REDIS_NODE_CM_CONF_NAME := ${REDIS_NODE}-conf-cm
REDIS_NODE_CM_SH_NAME := ${REDIS_NODE}-sh-cm
REDIS_NODE_VOL_CONF_NAME = conf
REDIS_NODE_VOL_SH_NAME = sh
REDIS_NODE_PVC_NAME = persitent


REDIS_NODE_POD_HOST_SUFFIX = svc.cluster.local
REDIS_NODE_SH_LOG_FILENAME = shlog
REDIS_NODE_KEY_NAMESPACE = redis-cluster
REDIS_NODE_KEY_COUNT = 2000

REDIS_NODE_CLUSTER_CONFIG_FILENAME = nodes.conf
REDIS_NODE_CLUSTER_OP_SH_FILENAME = cluster-op.sh
REDIS_NODE_FIX_IP_SH_FILENAME = fix-ip.sh
REDIS_NODE_POST_START_SH_FILENAME = post-start.sh
REDIS_NODE_REDIS_CONF_FILENAME = redis.conf

REDIS_NODE_SCALE_DOWN_KEY = scale-down
REDIS_NODE_SCALE_DOWN_STATUS__NEED_TO_SCALE_DOWN = 1
REDIS_NODE_SCALE_DOWN_STATUS__SCALING = 2
REDIS_NODE_SCALE_DOWN_STATUS__FINISHED = 3

REDIS_NODE_POD_HOST_END_PART = ${REDIS_NODE_SERVICE}.${NAMESPACE}.${REDIS_NODE_POD_HOST_SUFFIX}

# = Webhook Vars =

WEBHOOK_CRT = $(shell cat webhook/tls/${ENV}/${WEBHOOK_CRT_FILE_NAME} | base64 | tr -d '\n')

WEBHOOK = webhook
WEBHOOK_LABEL := ${WEBHOOK}
WEBHOOK_NAME := ${WEBHOOK}

WEBHOOK_SERVICE := ${WEBHOOK}-svc
WEBHOOK_CONFIG_NAME := ${WEBHOOK}-scale-down-config

WEBHOOK_SECRET_TLS_NAME := ${WEBHOOK}-tls-secrets
WEBHOOK_VOL_TLS_NAME = tls

WEBHOOK_KEY_FILE_NAME = tls.key
WEBHOOK_CRT_FILE_NAME = tls.crt

# = Scaler Vars =

SCALER = scaler
SCALER_LABEL := ${SCALER}
SCALER_NAME := ${SCALER}

SCALER_CM_SH_NAME := ${SCALER}-sh-cm
SCALER_VOL_SH_NAME = sh

SCALER_SH_FILENAME := ${SCALER}.sh

# ================================================
# ================ Deploy Commands ===============
# ================================================

# Deploy to Minikube

.PHONY: go
go: minikube-status clean
	@sleep 15
	@make deploy-webhook
	@sleep 5
	@make deploy-redis-node
	@sleep 5
	@make deploy-scaler
	@echo --Finished Deploy--

# = Debug =

.PHONY: debug-redis-node
debug-redis-node: clean-all-redis-node deploy-redis-node
	@sleep 1
	@kubectl get po -o wide
	@sleep 1
	@kubectl get po -w

.PHONY: debug-webhook
debug-webhook: clean-all-webhook deploy-webhook
	@sleep 1
	@kubectl get po -o wide
	@sleep 1
	@kubectl get po -w

.PHONY: debug-scaler
debug-scaler: clean-all-scaler deploy-scaler
	@sleep 1
	@kubectl get po -o wide
	@sleep 1
	@kubectl get po -w

.PHONY: clean
clean: clean-all-webhook clean-all-scaler clean-all-redis-node
	@echo --Finished Clean All Resources--

# = Deploy Redis Node =

.PHONY: deploy-redis-node
deploy-redis-node: init-ns init-redis-node-cm init-redis-node-svc init-redis-node init-redis-node-hpa
	@echo --Finished Deploy Redis Node--

.PHONY: clean-all-redis-node
clean-all-redis-node: clean-redis-node clean-redis-node-hpa clean-redis-node-svc clean-redis-node-cm clean-redis-node-pv clean-redis-node-pvc
	@echo --Finished Clean All Redis Node--

# = Deploy Webhook =

.PHONY: deploy-webhook
deploy-webhook: init-ns init-webhook-secrets init-webhook-svc init-webhook
	@sleep 5
	@make init-webhook-config
	@ # webhook-config will stop service to select pods, if run it to fast.
	@echo --Finished Deploy Webhook--

.PHONY: clean-all-webhook
clean-all-webhook: clean-webhook-config clean-webhook clean-webhook-svc clean-webhook-secrets
	@echo --Finished Clean All Webhook--

# = Deploy Scaler =

.PHONY: deploy-scaler
deploy-scaler: init-ns init-scaler-cm
	@sleep 3
	@make init-scaler
	@echo --Finished Deploy Scaler--

.PHONY: clean-all-scaler
clean-all-scaler: clean-scaler clean-scaler-cm
	@echo --Finished Clean All Scaler--

# ================================================
# ============== Minikube Commands ===============
# ================================================

.PHONY: minikube-status
minikube-status:
	@minikube status
	@sleep 1

# ================================================
# ================ Init Commands =================
# ================================================

# = Scaler =

.PHONY: init-scaler
init-scaler: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ scaler_name }}/${SCALER_NAME}/g" \
		-e "s/{{ scaler_pod_replicas }}/${SCALER_POD_REPLICAS}/g" \
		-e "s/{{ scaler_vol_sh_name }}/${SCALER_VOL_SH_NAME}/g" \
		-e "s/{{ scaler_cm_sh_name }}/${SCALER_CM_SH_NAME}/g" \
		-e "s/{{ scaler_image }}/${SCALER_IMAGE}/g" \
		-e "s/{{ scaler_sh_filename }}/${SCALER_SH_FILENAME}/g" \
		-e "s/{{ scaler_label }}/${SCALER_LABEL}/g" \
		-e "s/{{ redis_node_pod_host_end_part }}/${REDIS_NODE_POD_HOST_END_PART}/g" \
		-e "s/{{ redis_node_min_pod_replicas }}/${REDIS_NODE_MIN_POD_REPLICAS}/g" \
		-e "s/{{ redis_node_client_port }}/${REDIS_NODE_CLIENT_PORT}/g" \
		-e "s/{{ redis_node_name }}/${REDIS_NODE_NAME}/g" \
		-e "s/{{ redis_node_key_namespace }}/${REDIS_NODE_KEY_NAMESPACE}/g" \
		-e "s/{{ redis_node_scale_down_key }}/${REDIS_NODE_SCALE_DOWN_KEY}/g" \
		-e "s/{{ redis_node_key_count }}/${REDIS_NODE_KEY_COUNT}/g" \
		-e "s/{{ redis_node_scale_down_status__need_to_scale_down }}/${REDIS_NODE_SCALE_DOWN_STATUS__NEED_TO_SCALE_DOWN}/g" \
		-e "s/{{ redis_node_scale_down_status__scaling }}/${REDIS_NODE_SCALE_DOWN_STATUS__SCALING}/g" \
		-e "s/{{ redis_node_scale_down_status__finished }}/${REDIS_NODE_SCALE_DOWN_STATUS__FINISHED}/g" \
		scaler/deploy/Deployment.yaml | \
		tee last_deploy/Scaler-Deployment.yaml | \
		kubectl apply -f -

.PHONY: init-scaler-cm
init-scaler-cm: init-ns
	@kubectl create configmap ${SCALER_CM_SH_NAME} \
		--namespace=${NAMESPACE} \
		--from-file="scaler/sh/${SCALER_SH_FILENAME}" \
		--save-config --dry-run -o yaml | \
		tee last_deploy/Scaler-SH-ConfigMap.yaml | \
		kubectl apply -f -
	@kubectl label cm ${SCALER_CM_SH_NAME} app=${SCALER_LABEL} --overwrite=true

# = Webhook =

.PHONY: init-webhook-config
init-webhook-config: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ webhook_config_name }}/${WEBHOOK_CONFIG_NAME}/g" \
		-e "s/{{ webhook_service }}/${WEBHOOK_SERVICE}/g" \
		-e "s/{{ webhook_crt }}/${WEBHOOK_CRT}/g" \
		-e "s/{{ webhook_label }}/${WEBHOOK_LABEL}/g" \
		-e "s/{{ redis_node_label }}/${REDIS_NODE_LABEL}/g" \
		-e "s/{{ redis_node_pod_host_suffix }}/${REDIS_NODE_POD_HOST_SUFFIX}/g" \
		webhook/deploy/ValidatingWebhookConfiguration.yaml | \
		tee last_deploy/Webhook-ValidatingWebhookConfiguration.yaml | \
		kubectl apply -f -

.PHONY: init-webhook
init-webhook: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ webhook_name }}/${WEBHOOK_NAME}/g" \
		-e "s/{{ webhook_port }}/${WEBHOOK_PORT}/g" \
		-e "s/{{ webhook_pod_replicas }}/${WEBHOOK_POD_REPLICAS}/g" \
		-e "s/{{ webhook_image }}/${WEBHOOK_IMAGE}/g" \
		-e "s/{{ webhook_secret_tls_name }}/${WEBHOOK_SECRET_TLS_NAME}/g" \
		-e "s/{{ webhook_cm_py_name }}/${WEBHOOK_CM_PY_NAME}/g" \
		-e "s/{{ webhook_vol_tls_name }}/${WEBHOOK_VOL_TLS_NAME}/g" \
		-e "s/{{ webhook_vol_py_name }}/${WEBHOOK_VOL_PY_NAME}/g" \
		-e "s/{{ webhook_port }}/${WEBHOOK_PORT}/g" \
		-e "s/{{ webhook_vol_tls_name }}/${WEBHOOK_VOL_TLS_NAME}/g" \
		-e "s/{{ webhook_key_file_name }}/${WEBHOOK_KEY_FILE_NAME}/g" \
		-e "s/{{ webhook_crt_file_name }}/${WEBHOOK_CRT_FILE_NAME}/g" \
		-e "s/{{ webhook_label }}/${WEBHOOK_LABEL}/g" \
		-e "s/{{ redis_node_min_pod_replicas }}/${REDIS_NODE_MIN_POD_REPLICAS}/g" \
		-e "s/{{ redis_node_client_port }}/${REDIS_NODE_CLIENT_PORT}/g" \
		-e "s/{{ redis_node_name }}/${REDIS_NODE_NAME}/g" \
		-e "s/{{ redis_node_pod_host_end_part }}/${REDIS_NODE_POD_HOST_END_PART}/g" \
		-e "s/{{ redis_node_key_namespace }}/${REDIS_NODE_KEY_NAMESPACE}/g" \
		-e "s/{{ redis_node_scale_down_key }}/${REDIS_NODE_SCALE_DOWN_KEY}/g" \
		-e "s/{{ redis_node_scale_down_status__need_to_scale_down }}/${REDIS_NODE_SCALE_DOWN_STATUS__NEED_TO_SCALE_DOWN}/g" \
		-e "s/{{ redis_node_scale_down_status__scaling }}/${REDIS_NODE_SCALE_DOWN_STATUS__SCALING}/g" \
		-e "s/{{ redis_node_scale_down_status__finished }}/${REDIS_NODE_SCALE_DOWN_STATUS__FINISHED}/g" \
		webhook/deploy/Deployment.yaml | \
		tee last_deploy/Webhook-Deployment.yaml | \
		kubectl apply -f -

.PHONY: init-webhook-svc
init-webhook-svc: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ webhook_service }}/${WEBHOOK_SERVICE}/g" \
		-e "s/{{ webhook_port }}/${WEBHOOK_PORT}/g" \
		-e "s/{{ webhook_label }}/${WEBHOOK_LABEL}/g" \
		webhook/deploy/Service.yaml | \
		tee last_deploy/Webhook-Service.yaml | \
		kubectl apply -f -

.PHONY: init-webhook-secrets
init-webhook-secrets: init-ns
	@kubectl create secret tls ${WEBHOOK_SECRET_TLS_NAME} \
		--namespace=${NAMESPACE} \
		--key webhook/tls/${ENV}/${WEBHOOK_KEY_FILE_NAME} \
		--cert webhook/tls/${ENV}/${WEBHOOK_CRT_FILE_NAME} \
		--save-config --dry-run -o yaml | \
		tee last_deploy/Webhook-Secret.yaml | \
		kubectl apply -f -
	@kubectl label secret ${WEBHOOK_SECRET_TLS_NAME} app=${WEBHOOK_LABEL} --overwrite=true

# = Redis-Node =

.PHONY: init-redis-node
init-redis-node: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ redis_node_name }}/${REDIS_NODE_NAME}/g" \
		-e "s/{{ redis_node_service }}/${REDIS_NODE_SERVICE}/g" \
		-e "s/{{ redis_node_client_port }}/${REDIS_NODE_CLIENT_PORT}/g" \
		-e "s/{{ redis_node_gossip_port }}/${REDIS_NODE_GOSSIP_PORT}/g" \
		-e "s/{{ redis_node_min_pod_replicas }}/${REDIS_NODE_MIN_POD_REPLICAS}/g" \
		-e "s/{{ redis_node_pvc_name }}/${REDIS_NODE_PVC_NAME}/g" \
		-e "s/{{ redis_node_storage }}/${REDIS_NODE_STORAGE}/g" \
		-e "s/{{ redis_node_vol_conf_name }}/${REDIS_NODE_VOL_CONF_NAME}/g" \
		-e "s/{{ redis_node_vol_sh_name }}/${REDIS_NODE_VOL_SH_NAME}/g" \
		-e "s/{{ redis_node_cm_conf_name }}/${REDIS_NODE_CM_CONF_NAME}/g" \
		-e "s/{{ redis_node_cm_sh_name }}/${REDIS_NODE_CM_SH_NAME}/g" \
		-e "s/{{ redis_node_image }}/${REDIS_NODE_IMAGE}/g" \
		-e "s/{{ redis_node_redis_conf_filename }}/${REDIS_NODE_REDIS_CONF_FILENAME}/g" \
		-e "s/{{ redis_node_post_start_sh_filename }}/${REDIS_NODE_POST_START_SH_FILENAME}/g" \
		-e "s/{{ redis_node_requests_memory }}/${REDIS_NODE_REQUESTS_MEMORY}/g" \
		-e "s/{{ redis_node_limits_memory }}/${REDIS_NODE_LIMITS_MEMORY}/g" \
		-e "s/{{ redis_node_readiness_filename }}/${REDIS_NODE_READINESS_FILENAME}/g" \
		-e "s/{{ redis_node_key_count }}/${REDIS_NODE_KEY_COUNT}/g" \
		-e "s/{{ redis_cluster_min_pod_replicas }}/${REDIS_CLUSTER_MIN_POD_REPLICAS}/g" \
		-e "s/{{ redis_node_key_namespace }}/${REDIS_NODE_KEY_NAMESPACE}/g" \
		-e "s/{{ redis_node_sh_log_filename }}/${REDIS_NODE_SH_LOG_FILENAME}/g" \
		-e "s/{{ redis_node_pod_host_end_part }}/${REDIS_NODE_POD_HOST_END_PART}/g" \
		-e "s/{{ redis_node_cluster_config_filename }}/${REDIS_NODE_CLUSTER_CONFIG_FILENAME}/g" \
		-e "s/{{ redis_node_vol_sh_name }}/${REDIS_NODE_VOL_SH_NAME}/g" \
		-e "s/{{ redis_node_fix_ip_sh_filename }}/${REDIS_NODE_FIX_IP_SH_FILENAME}/g" \
		-e "s/{{ redis_node_cluster_op_sh_filename }}/${REDIS_NODE_CLUSTER_OP_SH_FILENAME}/g" \
		-e "s/{{ redis_node_label }}/${REDIS_NODE_LABEL}/g" \
		redis-node/deploy/StatefulSet.yaml | \
		tee last_deploy/Redis-Node-StatefulSet.yaml | \
		kubectl apply -f -

.PHONY: init-redis-node-hpa
init-redis-node-hpa: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ redis_node_hpa_name }}/${REDIS_NODE_HPA_NAME}/g" \
		-e "s/{{ redis_node_name }}/${REDIS_NODE_NAME}/g" \
		-e "s/{{ redis_node_average_value }}/${REDIS_NODE_AVERAGE_VALUE}/g" \
		-e "s/{{ redis_node_min_pod_replicas }}/${REDIS_NODE_MIN_POD_REPLICAS}/g" \
		-e "s/{{ redis_node_max_pod_replicas }}/${REDIS_NODE_MAX_POD_REPLICAS}/g" \
		-e "s/{{ redis_node_label }}/${REDIS_NODE_LABEL}/g" \
		redis-node/deploy/HorizontalPodAutoscaler.yaml | \
		tee last_deploy/Redis-Node-HorizontalPodAutoscaler.yaml | \
		kubectl apply -f -

.PHONY: init-redis-node-svc
init-redis-node-svc: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ redis_node_service }}/${REDIS_NODE_SERVICE}/g" \
		-e "s/{{ redis_node_client_port }}/${REDIS_NODE_CLIENT_PORT}/g" \
		-e "s/{{ redis_node_gossip_port }}/${REDIS_NODE_GOSSIP_PORT}/g" \
		-e "s/{{ redis_node_label }}/${REDIS_NODE_LABEL}/g" \
		redis-node/deploy/Service.yaml | \
		tee last_deploy/Redis-Node-Service.yaml | \
		kubectl apply -f -

.PHONY: init-redis-node-cm
init-redis-node-cm: init-ns
	@sed -e "s/{{ namespace }}/${NAMESPACE}/g" \
		-e "s/{{ redis_node_cm_conf_name }}/${REDIS_NODE_CM_CONF_NAME}/g" \
		-e "s/{{ redis_node_redis_conf_filename }}/${REDIS_NODE_REDIS_CONF_FILENAME}/g" \
		-e "s/{{ redis_node_cluster_config_filename }}/${REDIS_NODE_CLUSTER_CONFIG_FILENAME}/g" \
		-e "s/{{ redis_node_maxmemory }}/${REDIS_NODE_MAXMEMORY}/g" \
		-e "s/{{ redis_node_label }}/${REDIS_NODE_LABEL}/g" \
		redis-node/deploy/ConfigMap.yaml | \
		tee last_deploy/Redis-Node-Conf-ConfigMap.yaml | \
		kubectl apply -f -
	@kubectl create configmap ${REDIS_NODE_CM_SH_NAME} \
		--namespace=${NAMESPACE} \
		--from-file="redis-node/sh/${REDIS_NODE_CLUSTER_OP_SH_FILENAME}" \
		--from-file="redis-node/sh/${REDIS_NODE_FIX_IP_SH_FILENAME}" \
		--from-file="redis-node/sh/${REDIS_NODE_POST_START_SH_FILENAME}" \
		--save-config --dry-run -o yaml | \
		tee last_deploy/Redis-Node-SH-ConfigMap.yaml | \
		kubectl apply -f -
	@kubectl label cm ${REDIS_NODE_CM_SH_NAME} app=${REDIS_NODE_LABEL} --overwrite=true

# = Common =

.PHONY: init-ns
init-ns:
	@sed -e "s/{{ namespace_prd }}/${NAMESPACE_PRD}/g" \
		-e "s/{{ namespace_dev }}/${NAMESPACE_DEV}/g" \
		common/deploy/Namespace.yaml | \
		tee last_deploy/Namespace.yaml | \
		kubectl apply -f -
	@make set-ns

# ================================================
# ================ Clean Commands ================
# ================================================

# = Scaler =

.PHONY: clean-scaler
clean-scaler: set-ns
	@kubectl delete deploy -l app=${SCALER_LABEL}
	@kubectl get deploy -l app=${SCALER_LABEL}
	@echo --Finished Clean Deployment with app=${SCALER_LABEL} label--

.PHONY: clean-scaler-cm
clean-scaler-cm: set-ns
	@kubectl delete cm -l app=${SCALER_LABEL}
	@kubectl get cm -l app=${SCALER_LABEL}
	@echo --Finished Clean ConfigMaps with app=${SCALER_LABEL} label--

# = Webhook =

.PHONY: clean-webhook
clean-webhook: set-ns
	@kubectl delete deploy -l app=${WEBHOOK_LABEL}
	@kubectl get deploy -l app=${WEBHOOK_LABEL}
	@echo --Finished Clean Deployment with app=${WEBHOOK_LABEL} label--

.PHONY: clean-webhook-config
clean-webhook-config: set-ns
	@kubectl delete validatingwebhookconfigurations -l app=${WEBHOOK_LABEL}
	@kubectl get validatingwebhookconfigurations -l app=${WEBHOOK_LABEL}
	@echo --Finished Clean ValidatingWebhookConfiguration with app=${WEBHOOK_LABEL} label--

.PHONY: clean-webhook-secrets
clean-webhook-secrets: set-ns
	@kubectl delete secrets -l app=${WEBHOOK_LABEL}
	@kubectl get secrets -l app=${WEBHOOK_LABEL}
	@echo --Finished Clean Secret with app=${WEBHOOK_LABEL} label--

.PHONY: clean-webhook-svc
clean-webhook-svc: set-ns
	@kubectl delete svc -l app=${WEBHOOK_LABEL}
	@kubectl get svc -l app=${WEBHOOK_LABEL}
	@echo --Finished Clean Services with app=${WEBHOOK_LABEL} labels--

# = Redis-Node =

.PHONY: clean-redis-node
clean-redis-node: set-ns
	@kubectl delete sts -l app=${REDIS_NODE_LABEL}
	@kubectl get sts -l app=${REDIS_NODE_LABEL}
	@echo --Finished Clean StatefulSet with app=${REDIS_NODE_LABEL} label--

.PHONY: clean-redis-node-pvc
clean-redis-node-pvc: set-ns
	@kubectl delete pvc -l app=${REDIS_NODE_LABEL}
	@kubectl get pvc -l app=${REDIS_NODE_LABEL}
	@echo --Finished Clean PVC with app=${REDIS_NODE_LABEL} label--

.PHONY: clean-redis-node-pv
clean-redis-node-pv: set-ns
	@kubectl delete pv -l app=${REDIS_NODE_LABEL}
	@kubectl get pv -l app=${REDIS_NODE_LABEL}
	@echo --Finished Clean PV with app=${REDIS_NODE_LABEL} label--

.PHONY: clean-redis-node-hpa
clean-redis-node-hpa: set-ns
	@kubectl delete hpa -l app=${REDIS_NODE_LABEL}
	@kubectl get hpa -l app=${REDIS_NODE_LABEL}
	@echo --Finished Clean HorizontalPodAutoscaler with app=${REDIS_NODE_LABEL} label--

.PHONY: clean-redis-node-svc
clean-redis-node-svc: set-ns
	@kubectl delete svc -l app=${REDIS_NODE_LABEL}
	@kubectl get svc -l app=${REDIS_NODE_LABEL}
	@echo --Finished Clean Services with app=${REDIS_NODE_LABEL} labels--

.PHONY: clean-redis-node-cm
clean-redis-node-cm: set-ns
	@kubectl delete cm -l app=${REDIS_NODE_LABEL}
	@kubectl get cm -l app=${REDIS_NODE_LABEL}
	@echo --Finished Clean ConfigMaps with app=${REDIS_NODE_LABEL} labels--

# = Common =

.PHONY: clean-dev-ns
clean-dev-ns:
	@kubectl delete ns -l app=${NAMESPACE_DEV}
	@kubectl get ns -l app=${NAMESPACE_DEV}
	@echo --Finished Clean Namespaces--

.PHONY: clean-prd-ns
clean-prd-ns:
	@kubectl delete ns -l app=${NAMESPACE_PRD}
	@kubectl get ns -l app=${NAMESPACE_PRD}
	@echo --Finished Clean Namespaces--

.PHONY: set-ns
set-ns:
	@kubectl config set-context --current --namespace=${NAMESPACE}

endif
