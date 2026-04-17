BUILDPACK_ID      ?= renku/opencode
BUILDPACK_VERSION ?= 0.1.0
PACK_IMAGE        ?= renku-opencode-buildpack:$(BUILDPACK_VERSION)
SELECTOR          ?= ghcr.io/swissdatasciencecenter/renku-frontend-buildpacks/selector:0.4.0
SAMPLE            ?= samples/jupyterlab-opencode
SAMPLE_IMAGE      ?= renku-opencode-sample:latest

.PHONY: help package sample run shellcheck clean

help:
	@echo "Targets:"
	@echo "  package      Build a CNB buildpack image ($(PACK_IMAGE))"
	@echo "  sample       Build a sample Renku session image from $(SAMPLE)"
	@echo "  run          Run the sample image locally (ttyd on :8000)"
	@echo "  shellcheck   Lint bin/ scripts"
	@echo "  clean        Remove local buildpack + sample images"

package:
	pack config experimental true >/dev/null
	pack buildpack package $(PACK_IMAGE) --config package.toml --format image

sample: package
	pack build $(SAMPLE_IMAGE) \
	  --builder $(SELECTOR) \
	  --buildpack $(PACK_IMAGE) \
	  --env BP_RENKU_FRONTENDS=jupyterlab,opencode \
	  --path $(SAMPLE)

run:
	docker run --rm -it \
	  -p 8000:8000 \
	  -e RENKU_SESSION_IP=0.0.0.0 \
	  -e RENKU_SESSION_PORT=8000 \
	  -v $(PWD)/samples/_secrets:/secrets:ro \
	  $(SAMPLE_IMAGE)

shellcheck:
	shellcheck bin/detect bin/build bin/opencode-init.sh

clean:
	-docker rmi $(PACK_IMAGE) $(SAMPLE_IMAGE) 2>/dev/null || true
