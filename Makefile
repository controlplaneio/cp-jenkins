NAME := cp-jenkins
PKG := github.com/controlplane/$(NAME)
REGISTRY := docker.io/controlplane

VIRTUAL_HOST ?= ""
LETSENCRYPT_EMAIL ?= ""

CACHE_BUSTER=$$(date)

TEST_HTTP_PORT=8090

JENKINS_HOME_MOUNT_DIR ?= /mnt/jenkins_home/
JENKINS_TESTING_REPO_MOUNT_DIR ?= $${HOME}/src/
# e.g. "file:///mnt/test-repo/some-repo"

JENKINS_LOCAL_JOB_OVERRIDE ?= ""
JENKINS_DSL_OVERRIDE ?= ""

SHELL := /bin/bash
BUILD_DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

GIT_MESSAGE := $(shell git -c log.showSignature=false log --max-count=1 --pretty=format:"%H")
GIT_SHA := $(shell git log -1 --format=%h)
GIT_TAG ?= $(shell bash -c 'TAG=$$(git tag | tail -n1); echo "$${TAG:-none}"')

GIT_UNTRACKED_CHANGES := $(shell git status --porcelain --untracked-files=no)
ifneq ($(GIT_UNTRACKED_CHANGES),)
	GIT_COMMIT := $(GIT_COMMIT)-dirty
endif

CONTAINER_TAG ?= $(GIT_TAG)
CONTAINER_NAME := $(REGISTRY)/$(NAME):$(CONTAINER_TAG)
CONTAINER_NAME_LATEST := $(REGISTRY)/$(NAME):latest

export NAME REGISTRY BUILD_DATE GIT_MESSAGE GIT_SHA GIT_TAG CONTAINER_TAG CONTAINER_NAME

.PHONY: all
all: help

.PHONY: secrets-create
secrets-create: ## write secrets to the Jenkins API
	@echo "+ $@"
	script/populate-secrets.sh

.PHONY: secrets-delete
secrets-delete: ## delete secrets from the Jenkins API
	@echo "+ $@"
	script/populate-secrets.sh --delete

.PHONY: test-secrets
secrets-test: ## test secrets
	@echo "+ $@"
	script/test.sh

.PHONY: build
build: pull-base-image ## builds a Docker image, cachebusting for plugins
	@echo "+ $@"
	docker build \
		--tag "$(CONTAINER_NAME)" \
		--build-arg FOOTER_URL="$(VIRTUAL_HOST)" \
		--build-arg CACHE_BUSTER="$(CACHE_BUSTER)" \
		.
	docker tag "$(CONTAINER_NAME)" "$(CONTAINER_NAME_LATEST)"

.PHONY: build-with-cache
build-with-cache: ## builds a Docker image, keeping the cache intact
	@echo "+ $@"
	CACHE_BUSTER=KEEP_CACHE
	export CACHE_BUSTER CONTAINER_NAME VIRTUAL_HOST; make build

.PHONY: pull-base-image
pull-base-image: ## pulls a Docker base image
	@echo "+ $@"
	grep FROM Dockerfile | awk '{print $$2}' | xargs -n 1 docker pull

.PHONY: push
push: ## pushes a docker image
	@echo "+ $@"
	docker push "$(CONTAINER_NAME)"
	docker push "$(CONTAINER_NAME_LATEST)"

.PHONY: mount-point
mount-point: ## creates a mount point for the image volume
	@echo "+ $@"
	[[ -d $(JENKINS_HOME_MOUNT_DIR) ]] || mkdir -p $(JENKINS_HOME_MOUNT_DIR)
	[[ -d $(JENKINS_HOME_MOUNT_DIR)/.ssh/ ]] || mkdir -p $(JENKINS_HOME_MOUNT_DIR)/.ssh/
	chown $${USER} $(JENKINS_HOME_MOUNT_DIR) -R;

.PHONY: test-run
test-run: ## runs the last built docker image with ephemeral storage
	@echo "+ $@"
	docker rm --force jenkins-test || true
	if [[ -n "$$(cat /tmp/jenkins-test.cid)" ]]; then \
		docker ps -q \
			--filter "id=$$(cat /tmp/jenkins-test.cid)" \
		| xargs --no-run-if-empty docker kill; \
	fi
	rm -f /tmp/jenkins-test.cid || true
	echo "Target port is localhost:$(TEST_HTTP_PORT)"

	docker run \
		--name jenkins-test \
		-d \
		--group-add docker \
		--cidfile /tmp/jenkins-test.cid \
		-e GITHUB_OAUTH=test \
		-e JENKINS_DSL_OVERRIDE=$(JENKINS_DSL_OVERRIDE) \
		-e JENKINS_LOCAL_JOB_OVERRIDE=$(JENKINS_LOCAL_JOB_OVERRIDE) \
		-e JENKINS_SETUP_YAML="/usr/share/jenkins/config/setup.yml" \
		-e JENKINS_SECRET_YAML="/usr/share/jenkins/config/setup-secret-example.yml" \
		-p $(TEST_HTTP_PORT):8080 \
		-p 50090:50000 \
		--tmpfs /usr/share/jenkins/config/ \
		-v "$(JENKINS_TESTING_REPO_MOUNT_DIR)":/mnt/test-repo \
		-v /var/run/docker.sock:/var/run/docker.sock \
		"$(CONTAINER_NAME)"

	COUNT=0; \
	until [[ "$$(docker inspect -f {{.State.Running}} jenkins-test)" == "true" ]]; do \
			sleep 0.5; \
			if [[ $$((COUNT++)) -gt 10 ]]; then echo 'Container did not start'; exit 1; fi; \
	done;

	cat "$(shell pwd)/setup.yml" \
  			| docker exec -i jenkins-test sh -c "cat >/usr/share/jenkins/config/setup.yml"
	cat "$(shell pwd)/setup-secret-example.yml" \
				| docker exec -i jenkins-test sh -c "cat >/usr/share/jenkins/config/setup-secret-example.yml"

.PHONY: run-local
run-local: mount-point ## runs the last built docker image with persistent storage
	@echo "+ $@"
	docker rm --force jenkins || true
	docker run \
	  --name jenkins \
	  --rm \
	  --group-add docker \
	  -e GITHUB_OAUTH=none \
	  -e JENKINS_DSL_OVERRIDE=$(JENKINS_DSL_OVERRIDE) \
	  -e JENKINS_LOCAL_JOB_OVERRIDE=$(JENKINS_LOCAL_JOB_OVERRIDE) \
		-p 8080:8080 \
		-p 50000:50000 \
		-v "$(shell pwd)/setup.yml":/usr/share/jenkins/setup.yml \
		-v "$(shell pwd)/setup-secret.yml":/usr/share/jenkins/setup-secret.yml \
		-v "$(JENKINS_HOME_MOUNT_DIR)":/var/jenkins_home \
		-v "$(JENKINS_TESTING_REPO_MOUNT_DIR):/mnt/test-repo" \
		-v /var/run/docker.sock:/var/run/docker.sock \
		"$(CONTAINER_NAME)"

.PHONY: run
run: mount-point ## runs the last built docker image with persistent storage
	@echo "+ $@"
	docker rm --force jenkins || true
	docker run \
		--name jenkins \
		--rm \
		--group-add docker \
		-e GITHUB_OAUTH=test \
		-e JENKINS_DSL_OVERRIDE=$(JENKINS_DSL_OVERRIDE) \
		-e JENKINS_LOCAL_JOB_OVERRIDE=$(JENKINS_LOCAL_JOB_OVERRIDE) \
		-p 8080:8080 \
		-p 50000:50000 \
		-v "$(shell pwd)/setup.yml":/usr/share/jenkins/setup.yml \
		-v "$(shell pwd)/setup-secret.yml":/usr/share/jenkins/setup-secret.yml \
		-v "$(JENKINS_HOME_MOUNT_DIR)":/var/jenkins_home \
		-v "$(JENKINS_TESTING_REPO_MOUNT_DIR):/mnt/test-repo" \
		-v /var/run/docker.sock:/var/run/docker.sock \
		"$(CONTAINER_NAME)"

.PHONY: run-prod
run-prod: run-prod-nginx ## runs production build with nginx TLS
	@echo "+ $@"
	ID=$$(docker run \
		--restart always \
		--name jenkins \
		-d \
		--group-add docker \
		-e VIRTUAL_PORT="8080" \
		-e VIRTUAL_HOST="$(VIRTUAL_HOST)" \
		-e LETSENCRYPT_HOST="$(VIRTUAL_HOST)" \
		-e LETSENCRYPT_EMAIL="$(LETSENCRYPT_EMAIL)" \
		-e LETSENCRYPT_TEST='false' \
		--expose 8080 \
		-p 50000:50000 \
		-v "$(shell pwd)/setup.yml":/usr/share/jenkins/setup.yml \
		-v "$(shell pwd)/setup-secret.yml":/usr/share/jenkins/setup-secret.yml \
		-v "$(JENKINS_HOME_MOUNT_DIR)":/var/jenkins_home \
		-v /var/run/docker.sock:/var/run/docker.sock \
		"$(CONTAINER_NAME)") && docker logs -f "$${ID}"

.PHONY: run-prod-nginx
run-prod-nginx: ## run nginx with TLS
	@echo "+ $@"
	pwd
	docker rm --force nginx-proxy || true
	docker rm --force nginx-proxy-companion || true

	docker run -d \
		-p 80:80 \
		-p 443:443 \
		--restart always \
		--name nginx-proxy \
		-v /mnt/certs:/etc/nginx/certs:ro \
		-v /etc/nginx/vhost.d \
		-v /usr/share/nginx/html \
		-v /var/run/docker.sock:/tmp/docker.sock:ro \
		--label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
		jwilder/nginx-proxy

	docker run -d \
		--restart always \
		--name nginx-proxy-companion \
		-v /mnt/certs:/etc/nginx/certs:rw \
		-v /var/run/docker.sock:/var/run/docker.sock:ro \
		--volumes-from nginx-proxy \
		jrcs/letsencrypt-nginx-proxy-companion

.PHONY: export
export: ## package jenkins up for transport
	docker save "$(CONTAINER_NAME)" -o "$(CONTAINER_NAME)".tgz
	tar czf jenkins-home.tgz "$(JENKINS_HOME_MOUNT_DIR)"
	tar czf jenkins.tgz jenkins-home.tgz "$(CONTAINER_NAME)".tgz
	echo "Written: "$(CONTAINER_NAME)".tgz"
	stat "$(CONTAINER_NAME)".tgz

.PHONY: test
test: ## build and test image
	./test.sh

.PHONY: clean
clean: ## remove temporary files from test-run
	sudo rm /tmp/user/1000/tmp.*jenkins-test -rf

.PHONY: help
help: ## parse jobs and descriptions from this Makefile
	@grep -E '^[ a-zA-Z0-9_-]+:([^=]|$$)' $(MAKEFILE_LIST) \
    | grep -Ev '^help\b[[:space:]]*:' \
    | sort \
    | awk 'BEGIN {FS = ":.*?##"}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
