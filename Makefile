ifndef VERSION_REF
	VERSION_REF ?= $(shell git describe --tags --always --dirty="-dev")
endif

GO := $(shell command -v go)

LDFLAGS := -ldflags='-s -w -X "main.VersionRef=$(VERSION_REF)"'
export GOFLAGS := -trimpath

GOFILES = $(shell find . -iname '*.go' | grep -v -e vendor -e _modules -e _cache -e /data/)
TEST_KUBECONFIG = .kube/kind-kubeapply-test.yaml

LAMBDAZIP := kubeapply-lambda-$(VERSION_REF).zip

# Main targets
.PHONY: kubeapply
kubeapply: data
	go build $(LDFLAGS) -o build/kubeapply ./cmd/kubeapply

.PHONY: install
install: data
	go install $(LDFLAGS) ./cmd/kubeapply

# Lambda and server-related targets
.PHONY: kubeapply-lambda
kubeapply-lambda: data
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build $(LDFLAGS) -tags lambda.norpc -o build/kubeapply-lambda ./cmd/kubeapply-lambda

.PHONY: kubeapply-lambda-kubeapply
kubeapply-lambda-kubeapply: data
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o build/kubeapply ./cmd/kubeapply

.PHONY: lambda-zip
lambda-zip: clean kubeapply-lambda kubeapply-lambda-kubeapply
	./scripts/create-lambda-bundle.sh $(LAMBDAZIP)

.PHONY: kubeapply-server
kubeapply-server: data
	go build $(LDFLAGS) -o build/kubeapply-server ./cmd/kubeapply-server

# Lambda image targets
.PHONY: build-lambda-image
build-lambda-image:
	docker build \
		-f Dockerfile.lambda \
		--build-arg VERSION_REF=$(VERSION_REF) \
		-t kubeapply-lambda:$(VERSION_REF) \
		.

.PHONY: publish-lambda-image
publish-lambda-image:
	imager buildpush . \
		-f Dockerfile.lambda \
		-d all \
		--repository=kubeapply-lambda \
		--build-arg VERSION_REF=$(VERSION_REF) \
		--extra-tag=$(VERSION_REF) \
		--destination-aliases regions.yaml \
		--platform linux/amd64

# Test and formatting targets
.PHONY: test
test: kubeapply data vet $(TEST_KUBECONFIG)
	PATH=$(CURDIR)/build:$$PATH KIND_ENABLED=true go test -count=1 -cover ./...

.PHONY: test-ci
test-ci: data vet
	# Kind is not supported in CI yet.
	# TODO: Get this working.
	PATH=$(CURDIR)/build:$$PATH KIND_ENABLED=false go test -count=1 -cover ./...

.PHONY: vet
vet: data
	go vet ./...

.PHONY: data
data: go-bindata
	go-bindata -pkg data -o ./data/data.go \
		-ignore=.*\.pyc \
		-ignore=.*__pycache__.* \
		./pkg/pullreq/templates/... \
		./scripts/...

.PHONY: fmtgo
fmtgo:
	goimports -w $(GOFILES)

.PHONY: fmtpy
fmtpy:
	autopep8 -i scripts/*py scripts/cluster-summary/cluster_summary.py

$(TEST_KUBECONFIG):
	./scripts/kindctl.sh start

.PHONY: go-bindata
go-bindata:
	@echo "DEBUGGING Go environment:"
	@echo "PATH: $$PATH"
	@echo "which go: $$(which go 2>&1 || echo 'go command not found')"
	@echo "go version: $$(go version 2>&1 || echo 'go version failed')"
	@echo "GO variable: $(GO)"
	@echo "End of debugging info"
ifeq (, $(shell which go-bindata))
	go install github.com/kevinburke/go-bindata/v4/...@latest
endif

.PHONY: clean
clean:
	rm -Rf *.zip .kube build vendor
