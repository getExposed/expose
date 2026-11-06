############################
# UI build (Node)
############################
FROM node:24.22.2-alpine@sha256:8a32c8cf649a49915a66e81e7a609223c708d0adabf288ee3f4077d765542f85 AS ui
WORKDIR /ui/web/expose

# Better caching
COPY web/expose/package.json web/expose/yarn.lock ./
RUN --mount=type=cache,target=/root/.cache/yarn \
    yarn install --frozen-lockfile

# Copy sources & build
COPY web/expose/ ./
RUN yarn build

############################
# Build stage (Go)
############################
FROM --platform=$BUILDPLATFORM golang:1.27.3-alpine@sha256:fa3d596898d9f126af7c01d14ee7597bab3f39cccf392ef36b69fe77cd681f18 AS build
WORKDIR /src

ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

# deps
RUN apk add --no-cache ca-certificates git

# Go mod download (cached)
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

# Bring in the app sources
COPY . .
# Bring the built UI into the repo path expected by statik
COPY --from=ui /ui/web/expose/dist ./web/expose/dist

# Metadata for -ldflags
ARG VERSION_PATH=github.com/getExposed/expose/internal/version
ARG GIT_COMMIT=unknown
ARG UI_VERSION=container
ARG BUILD_DATE=unknown

ENV CGO_ENABLED=0
ENV PATH="/go/bin:${PATH}"

# Install codegen tools, generate assets, run wire, then build
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    set -eux; \
    echo "BUILDPLATFORM=$BUILDPLATFORM TARGETPLATFORM=$TARGETPLATFORM TARGETOS=$TARGETOS TARGETARCH=$TARGETARCH"; \
    # tools install
    go install github.com/jkuri/statik@latest; \
    go install github.com/google/wire/cmd/wire@latest; \
    # generate embedded UI package: github.com/getExposed/expose/internal/ui/landing
    statik -f -dest ./internal/ui -p landing -src ./web/expose/dist; \
    # generate wire code
    wire ./cmd/expose-server; \
    # derive GOOS/GOARCH from TARGETPLATFORM when unset
    TO=${TARGETOS:-$(echo "$TARGETPLATFORM" | cut -d/ -f1)}; \
    TA=${TARGETARCH:-$(echo "$TARGETPLATFORM" | cut -d/ -f2)}; \
    echo "GOOS=$TO GOARCH=$TA"; \
    GOOS="$TO" GOARCH="$TA" \
      go build -trimpath \
        -ldflags "-s -w -X ${VERSION_PATH}.GitCommit=${GIT_COMMIT} -X ${VERSION_PATH}.UIVersion=${UI_VERSION} -X ${VERSION_PATH}.BuildDate=${BUILD_DATE}" \
        -o /out/expose-server ./cmd/expose-server

############################
# Runtime (distroless)
############################
FROM gcr.io/distroless/static:nonroot@sha256:25ac8f0c3b2334a9eb05452266bd4697864a8c8ef0ef71e5e6480d7f92868329 AS runtime
WORKDIR /app

COPY --from=build /out/expose-server /usr/local/bin/expose-server

EXPOSE 2000 2200
USER 65532:65532

ENTRYPOINT ["/usr/local/bin/expose-server"]
CMD ["-config", "/etc/expose/expose-server.yaml"]
