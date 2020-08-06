# syntax = docker/dockerfile-upstream:1.1.7-experimental

# THIS FILE WAS AUTOMATICALLY GENERATED, PLEASE DO NOT EDIT.
#
# Generated on 2020-08-11T14:39:54Z by kres ced23da-dirty.

ARG TOOLCHAIN

FROM autonomy/ca-certificates:v0.2.0-29-gdda8024 AS image-ca-certificates

FROM autonomy/fhs:v0.2.0-29-gdda8024 AS image-fhs

# base toolchain image
FROM ${TOOLCHAIN} AS toolchain
RUN apk --update --no-cache add bash curl build-base

# build tools
FROM toolchain AS tools
ENV GO111MODULE on
ENV CGO_ENABLED 0
RUN curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | bash -s -- -b /bin v1.30.0
ARG GOFUMPT_VERSION
RUN cd $(mktemp -d) \
	&& go mod init tmp \
	&& go get mvdan.cc/gofumpt/gofumports@${GOFUMPT_VERSION} \
	&& mv /go/bin/gofumports /bin/gofumports

# tools and sources
FROM tools AS base
WORKDIR /src
COPY ./go.mod .
COPY ./go.sum .
RUN go mod download
RUN go mod verify
COPY ./internal ./internal
COPY ./cmd ./cmd
RUN go list -mod=readonly all >/dev/null

# builds kres
FROM base AS kres-build
WORKDIR /src/cmd/kres
ARG VERSION_PKG="github.com/talos-systems/kres/internal/version"
ARG SHA
ARG TAG
RUN --mount=type=cache,target=/root/.cache/go-build go build -ldflags "-s -w -X ${VERSION_PKG}.Name=kres -X ${VERSION_PKG}.SHA=${SHA} -X ${VERSION_PKG}.Tag=${TAG}" -o /kres

# runs gofumpt
FROM base AS lint-gofumpt
RUN find . -name '*.pb.go' | xargs -r rm
RUN FILES="$(gofumports -l -local github.com/talos-systems/kres .)" && test -z "${FILES}" || (echo -e "Source code is not formatted with 'gofumports -w -local github.com/talos-systems/kres .':\n${FILES}"; exit 1)

# runs golangci-lint
FROM base AS lint-golangci-lint
COPY .golangci.yml .
ENV GOGC 50
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/root/.cache/golangci-lint golangci-lint run --config .golangci.yml

# runs unit-tests with race detector
FROM base AS unit-tests-race
ARG TESTPKGS
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/tmp CGO_ENABLED=1 go test -v -race -count 1 ${TESTPKGS}

# runs unit-tests
FROM base AS unit-tests-run
ARG TESTPKGS
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/tmp go test -v -covermode=atomic -coverprofile=coverage.txt -count 1 ${TESTPKGS}

FROM scratch AS kres
COPY --from=kres-build /kres /kres

FROM scratch AS unit-tests
COPY --from=unit-tests-run /src/coverage.txt /coverage.txt

FROM kres AS image-kres
COPY --from=image-fhs / /
COPY --from=image-ca-certificates / /
ENTRYPOINT ["/kres","gen"]

