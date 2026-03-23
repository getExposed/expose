############################
# UI build (Node)
############################
FROM node:24.14.0-alpine@sha256:7fddd9ddeae8196abf4a3ef2de34e11f7b1a722119f91f28ddf1e99dcafdf114 AS ui
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
FROM --platform=$BUILDPLATFORM golang:1.26.0-alpine@sha256:d4c4845f5d60c6a974c6000ce58ae079328d03ab7f721a0734277e69905473e5 AS build
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
FROM gcr.io/distroless/static:nonroot@sha256:e3f945647ffb95b5839c07038d64f9811adf17308b9121d8a2b87b6a22a80a39 AS runtime
WORKDIR /app

COPY --from=build /out/expose-server /usr/local/bin/expose-server

EXPOSE 2000 2200
USER 65532:65532

ENTRYPOINT ["/usr/local/bin/expose-server"]
CMD ["-config", "/etc/expose/expose-server.yaml"]
