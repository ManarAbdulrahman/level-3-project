.PHONY: up down init cluster-up install uninstall logs repos namespaces cluster-down clean provision

up: cluster-up init tests 

down: cluster-down

cluster-down:
	k3d cluster delete l3p

clean: logs
	
cluster-up:
	k3d cluster create l3p \
	    -p 80:80@loadbalancer \
	    -p 443:443@loadbalancer \
	    -p 30000-32767:30000-32767@server[0] \
	    -v /etc/machine-id:/etc/machine-id:ro \
	    -v /var/log/journal:/var/log/journal:ro \
	    -v /var/run/docker.sock:/var/run/docker.sock \
	    --k3s-server-arg '--no-deploy=traefik' \
	    --agents 3

init: logs repos namespaces install-ingress
platform: install-service-mesh install-ingress install-logging install-monitoring install-secrets
deplatform: delete-service-mesh delete-ingress delete-logging delete-monitoring delete-secrets

logs:
	touch output.log
	rm -f output.log
	touch output.log

repos:
	helm repo add stable https://kubernetes-charts.storage.googleapis.com/
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add elastic https://helm.elastic.co
	helm repo add fluent https://fluent.github.io/helm-charts
	helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
	helm repo update

namespaces:
	kubectl apply -f platform/namespaces


install-cicd:
	echo "cicd: install" | tee -a output.log
	kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
	kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/tekton-dashboard-release.yaml
	kubectl patch svc tekton-dashboard -n tekton-pipelines --type='json' -p '[{"op":"replace", "path":"/spec/type", "value":"NodePort"}]'
	kubectl apply -f https://raw.githubusercontent.com/tektoncd/catalog/master/task/git-clone/0.2/git-clone.yaml
	kubectl create configmap config-artifact-pvc \
                         --from-literal=size=10Gi \
                         --from-literal=storageClassName=manual \
                         -o yaml -n tekton-pipelines \
                         --dry-run=client | kubectl replace -f -
	sudo apt update
	sudo apt install -y gnupg
	sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3EFE0E0A2F2F60AA
	echo "deb http://ppa.launchpad.net/tektoncd/cli/ubuntu eoan main"|sudo tee /etc/apt/sources.list.d/tektoncd-ubuntu-cli.list
	sudo apt update && sudo apt install -y tektoncd-cli
delete-cicd:
	echo "cicd: delete" | tee -a output.log
	kubectl delete -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
	kubectl delete -f https://storage.googleapis.com/tekton-releases/dashboard/latest/tekton-dashboard-release.yaml

tests: front-end-test cart-test catalogue-test orders-test payment-test shipping-test users-test queue-master-test

front-end-test:
	kubectl apply -f front-end/sa.yaml -f front-end/pl-resource.yaml -f front-end/task.yaml  -f front-end/dep-task.yaml -f front-end/dep-pl.yaml -f front-end/dep-pr.yaml -n test

front-end-prod:
	Kubectl apply -f front-end/sa.yaml -f front-end/pl-resource.yaml  -f front-end/dep-task.yaml -f front-end/dep-tr.yaml -n prod

cart-test:
	kubectl apply -f carts/sa.yaml -f carts/pl-resource.yaml -f carts/task.yaml  -f carts/dep-task.yaml -f carts/dep-pl.yaml -f carts/dep-pr.yaml -n test

cart-prod:
	Kubectl apply -f carts/sa.yaml -f carts/pl-resource.yaml -f carts/dep-task.yaml -f carts/dep-tr.yaml -n prod

catalogue-test:
	kubectl apply -f catalogue/sa.yaml -f catalogue/pl-resource.yaml -f catalogue/task.yaml  -f catalogue/dep-task.yaml -f catalogue/dep-pl.yaml -f catalogue/dep-pr.yaml -n test

catalogue-prod:
	 Kubectl apply -f catalogue/sa.yaml -f catalogue/pl-resource.yaml -f catalogue/dep-task.yaml -f catalogue/dep-tr.yaml -n prod

orders-test:
	kubectl apply -f orders/sa.yaml -f orders/pl-resource.yaml -f orders/task.yaml  -f orders/dep-task.yaml -f orders/dep-pl.yaml -f orders/dep-pr.yaml -n test

orders-prod:
	Kubectl apply -f orders/sa.yaml -f orders/pl-resource.yaml -f orders/dep-task.yaml -f orders/dep-tr.yaml -n prod

payment-test:
	kubectl apply -f payment/sa.yaml -f payment/pl-resource.yaml -f payment/task.yaml  -f payment/dep-task.yaml -f payment/dep-pl.yaml -f payment/dep-pr.yaml -n test

payment-prod:
	Kubectl apply -f payment/sa.yaml -f payment/pl-resource.yaml -f payment/dep-task.yaml -f payment/dep-tr.yaml -n prod	

shipping-test:
	kubectl apply -f shipping/sa.yaml -f shipping/pl-resource.yaml -f shipping/task.yaml  -f shipping/dep-task.yaml -f shipping/dep-pl.yaml -f shipping/dep-pr.yaml -n test

shipping-prod:
	Kubectl apply -f shipping/sa.yaml -f shipping/pl-resource.yaml -f shipping/dep-task.yaml -f shipping/dep-tr.yaml -n prod

users-test:
	kubectl apply -f users/sa.yaml -f users/pl-resource.yaml -f users/task.yaml  -f users/dep-task.yaml -f users/dep-pl.yaml -f users/dep-pr.yaml -n test

users-prod:
	Kubectl apply -f users/sa.yaml -f users/pl-resource.yaml -f users/dep-task.yaml -f users/dep-tr.yaml -n prod

master-queue-test:
	kubectl apply -f queue-master/sa.yaml -f queue-master/pl-resource.yaml -f queue-master/task.yaml  -f queue-master/dep-task.yaml -f master-queue/dep-pl.yaml -f master-queue/dep-pr.yaml -n test

master-queue-prod:
	Kubectl apply -f queue/sa.yaml -f queue-master/pl-resource.yaml -f queue-master/dep-task.yaml -f queue-master/dep-tr.yaml -n prod

install-ingress:
	echo "Ingress: install" | tee -a output.log
	kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-0.32.0/deploy/static/provider/cloud/deploy.yaml | tee -a output.log
	kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
	kubectl apply -f ingress.yaml -n prod

delete-ingress:
	echo "Ingress: delete" | tee -a output.log
	kubectl delete -n ingress -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-0.32.0/deploy/static/provider/cloud/deploy.yaml | tee -a output.log 2>/dev/null | true
	kubectl apply -f ingress.yaml

install-prometheus:
	source pro-graf/pro-graf.sh 

install-logging:
	source elf/elf.sh
