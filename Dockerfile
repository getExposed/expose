############################
# UI build (Node)
############################
FROM node:24.20.0-alpine@sha256:e67514e5d0f6c46656005e1b693b2ec9d52e80b641307de684d4a015ba7a4eaf AS ui
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
FROM --platform=$BUILDPLATFORM golang:1.27.0-alpine@sha256:4c9fe60190a2a3350ddc51de80d0224b8a6698d12bdfc999fee45ea9d6c46dbc AS build
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
FROM gcr.io/distroless/static:nonroot@sha256:1c2c046bc09ed40fad370b599a0b1ae7987f55b01e247cf27a7c27cd97e5bbc7 AS runtime
WORKDIR /app

COPY --from=build /out/expose-server /usr/local/bin/expose-server

EXPOSE 2000 2200
USER 65532:65532

ENTRYPOINT ["/usr/local/bin/expose-server"]
CMD ["-config", "/etc/expose/expose-server.yaml"]
