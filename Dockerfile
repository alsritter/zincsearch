# syntax=docker/dockerfile:experimental
############################
# STEP 1 build web dist
############################
# 使用国内镜像源
FROM node:18.16.0-slim as webBuilder
WORKDIR /web
COPY ./web /web/

# 设置 npm 使用国内镜像源
RUN npm config set registry https://registry.npm.taobao.org
RUN npm install
RUN npm run build

############################
# STEP 2 build executable binary
############################
# 使用国内 golang 镜像
FROM public.ecr.aws/docker/library/golang:1.19 as builder
ARG VERSION
ARG COMMIT_HASH
ARG BUILD_DATE

RUN update-ca-certificates
ENV USER=zincsearch
ENV GROUP=zincsearch
ENV UID=10001
ENV GID=10001
RUN groupadd --gid "${GID}" "${GROUP}"
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    --gid "${GID}" \
    "${USER}"
RUN mkdir -p /var/lib/zincsearch /data && chown zincsearch:zincsearch /var/lib/zincsearch /data
WORKDIR $GOPATH/src/github.com/zincsearch/zincsearch/
COPY . .
COPY --from=webBuilder /web/dist web/dist

# 设置 Go 使用国内代理
ENV GOPROXY=https://goproxy.cn,direct
RUN go mod tidy

ENV VERSION=$VERSION
ENV COMMIT_HASH=$COMMIT_HASH
ENV BUILD_DATE=$BUILD_DATE

RUN CGO_ENABLED=0 go build -ldflags="-s -w -X github.com/zincsearch/zincsearch/pkg/meta.Version=${VERSION} -X github.com/zincsearch/zincsearch/pkg/meta.CommitHash=${COMMIT_HASH} -X github.com/zincsearch/zincsearch/pkg/meta.BuildDate=${BUILD_DATE}" -o zincsearch cmd/zincsearch/main.go

############################
# STEP 3 build a small image
############################
FROM ubuntu:latest

# Install basic network tools
RUN apt-get update && apt-get install -y \
    curl \
    dnsutils \
    net-tools \
    telnet \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Import the user and group files from the builder.
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Copy the ssl certificates
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy our static executable.
COPY --from=builder  /go/src/github.com/zincsearch/zincsearch/zincsearch /go/bin/zincsearch

# Create directories that can be used to keep ZincSearch data persistent along with host source or named volumes
COPY --from=builder --chown=zincsearch:zincsearch /var/lib/zincsearch /var/lib/zincsearch
COPY --from=builder --chown=zincsearch:zincsearch /data /data

# Port on which the service will be exposed.
EXPOSE 4080

# Run the zincsearch binary.
ENTRYPOINT ["/go/bin/zincsearch"]
