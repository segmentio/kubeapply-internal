# Fetch or build all required binaries
FROM golang:1.23.10 AS builder

ARG VERSION_REF
RUN test -n "${VERSION_REF}"

ENV SRC=github.com/segmentio/kubeapply

RUN apt-get update && apt-get install --yes \
    curl \
    unzip \
    wget

COPY . /go/src/${SRC}
RUN cd /usr/local/bin && /go/src/${SRC}/scripts/pull-deps.sh

WORKDIR /go/src/${SRC}

ENV CGO_ENABLED=1 \
    GO111MODULE=on

RUN make kubeapply VERSION_REF=${VERSION_REF} && \
    cp build/kubeapply /usr/local/bin

# Copy into final image
FROM ubuntu:24.04

RUN apt-get update && apt-get install --yes \
    curl \
    git \
    unzip \
    python3 \
    python3-pip

RUN curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

COPY --from=builder \
    /usr/local/bin/helm \
    /usr/local/bin/kubectl \
    /usr/local/bin/kubeapply \
    /usr/local/bin/
