NAME := cp-jenkins
PKG := github.com/controlplane/$(NAME)
REGISTRY := docker.io

SHELL := /bin/bash
BUILD_DATE := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

GIT_MESSAGE := $(shell git -c log.showSignature=false log --max-count=1 --pretty=format:"%H")
GIT_SHA := $(shell git log -1 --format=%h)
GIT_TAG ?= $(shell bash -c 'TAG=$$(git tag | tail -n1); echo "$${TAG:-none}"')

GIT_UNTRACKED_CHANGES := $(shell git status --porcelain --untracked-files=no)
ifneq ($(GIT_UNTRACKED_CHANGES),)
	GITCOMMIT := $(GITCOMMIT)-dirty
endif

CONTAINER_TAG ?= $(GIT_TAG)
CONTAINER_NAME := $(REGISTRY)/$(NAME):$(CONTAINER_TAG)

export NAME REGISTRY BUILD_DATE GIT_MESSAGE GIT_SHA GIT_TAG CONTAINER_TAG CONTAINER_NAME


.PHONY: all
all: build run

.PHONY: build
build: ## builds a docker image
	@echo "+ $@"
	docker build --tag "${CONTAINER_NAME}" .

.PHONY: run
run: ## runs the last build docker image
	@echo "+ $@"
	$(eval TMP_DIR = $(shell mktemp -d --suffix -jenkins-test))
	pwd
	docker run \
		-d \
		--rm \
		-p 8080:8080 \
		-p 50000:50000 \
		-v "$${HOME}.ssh/id_rsa:/var/jenkins_home/.ssh/" \
		-v "$(TMP_DIR)":/var/jenkins_home \
		-v "$(shell pwd)/setup.yml":/usr/share/jenkins/setup.yml \
		"${CONTAINER_NAME}"

.PHONY: help
help: ## parse jobs and descriptions from this Makefile
	@grep -E '^[ a-zA-Z0-9_-]+:([^=]|$$)' $(MAKEFILE_LIST) \
    | grep -Ev '^help\b[[:space:]]*:' \
    | sort \
    | awk 'BEGIN {FS = ":.*?##"}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

