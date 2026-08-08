IMAGE ?= $(USER)/qwen-comfyui
TAG   ?= latest

.DEFAULT_GOAL := help

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[1;34m%-16s\033[0m %s\n", $$1, $$2}'

build: ## Build the RunPod image
	docker build --platform linux/amd64 -t $(IMAGE):$(TAG) .

push: build ## Build and push to your registry
	docker push $(IMAGE):$(TAG)

run: ## Run locally (needs an NVIDIA GPU + nvidia-container-toolkit)
	docker run --rm -it --gpus all \
		-p 8188:8188 \
		-v $(PWD)/.volume:/workspace \
		-e MODELS=$${MODELS:-v23-sfw} \
		-e HF_TOKEN=$${HF_TOKEN:-} \
		$(IMAGE):$(TAG)

shell: ## Shell into the image without starting ComfyUI
	docker run --rm -it --gpus all -v $(PWD)/.volume:/workspace \
		--entrypoint bash $(IMAGE):$(TAG)

check: ## Lint the shell scripts and validate the workflow JSON
	@command -v shellcheck >/dev/null && shellcheck -S warning bootstrap.sh scripts/*.sh || echo "shellcheck not installed, skipping"
	@python3 -c "import json,glob,sys; [json.load(open(p)) for p in glob.glob('workflows/*.json')]; print('workflows: valid JSON')"
	@python3 -m py_compile scripts/*.py custom_nodes/qwen_edit_target_latent/__init__.py && echo "python: compiles"

.PHONY: help build push run shell check
