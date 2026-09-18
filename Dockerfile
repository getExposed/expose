############################
# UI build (Node)
############################
FROM node:24.21.0-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS ui
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
FROM --platform=$BUILDPLATFORM golang:1.27.1-alpine@sha256:4cb7ac979db5fcc41cae44b2227ba5ab8a51e8807f40d9ba4dee20a0ad960b5b AS build
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
FROM gcr.io/distroless/static:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3 AS runtime
WORKDIR /app

COPY --from=build /out/expose-server /usr/local/bin/expose-server

EXPOSE 2000 2200
USER 65532:65532

ENTRYPOINT ["/usr/local/bin/expose-server"]
CMD ["-config", "/etc/expose/expose-server.yaml"]
