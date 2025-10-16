############################
# UI build (Node)
############################
FROM node:22.20.0-alpine@sha256:dbcedd8aeab47fbc0f4dd4bffa55b7c3c729a707875968d467aaaea42d6225af AS ui
WORKDIR /ui
# bring in the UI sources
COPY web/expose ./web/expose
RUN --mount=type=cache,target=/root/.npm \
    sh -lc 'cd web/expose &&  yarn install && yarn build'

############################
# Build stage
############################
FROM --platform=$BUILDPLATFORM golang:1.25.3-alpine@sha256:aee43c3ccbf24fdffb7295693b6e33b21e01baec1b2a55acc351fde345e9ec34 AS build
WORKDIR /src

ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Faster, repeatable builds
RUN apk add --no-cache ca-certificates git
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Bring in the source
COPY . .
COPY --from=ui /ui/web/expose/dist ./web/expose/dist

# Build args for version info (optional)
ARG VERSION_PATH=github.com/getExposed/expose/internal/version
ARG GIT_COMMIT=unknown
ARG UI_VERSION=container
ARG BUILD_DATE=unknown

ENV CGO_ENABLED=0
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    set -eux; \
    echo "BUILDPLATFORM=$BUILDPLATFORM TARGETPLATFORM=$TARGETPLATFORM TARGETOS=$TARGETOS TARGETARCH=$TARGETARCH"; \
    test -n "$TARGETOS" && test -n "$TARGETARCH"; \
    GOOS="$TARGETOS" GOARCH="$TARGETARCH" \
      go build -trimpath \
        -ldflags "-s -w -X ${VERSION_PATH}.GitCommit=${GIT_COMMIT} -X ${VERSION_PATH}.UIVersion=${UI_VERSION} -X ${VERSION_PATH}.BuildDate=${BUILD_DATE}" \
        -o /out/expose-server ./cmd/expose-server

 ############################
 # Runtime stage
 ############################
 FROM gcr.io/distroless/static:nonroot@sha256:e8a4044e0b4ae4257efa45fc026c0bc30ad320d43bd4c1a7d5271bd241e386d0 AS runtime
 WORKDIR /app

 # Copy the server
 COPY --from=build /out/expose-server /usr/local/bin/expose-server

 # Ports the server listens on (HTTP and SSH)
 EXPOSE 2000 2200

 # Run as non-root
 USER 65532:65532

 # Expect a config at /etc/expose/expose-server.yaml (mount it)
 ENTRYPOINT ["/usr/local/bin/expose-server"]
 CMD ["-config", "/etc/expose/expose-server.yaml"]