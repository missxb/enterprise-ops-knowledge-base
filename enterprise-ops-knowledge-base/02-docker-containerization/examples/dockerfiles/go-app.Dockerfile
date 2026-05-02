# ============================================================
# Go 应用多阶段构建 Dockerfile
# 适用于 Go 微服务 / CLI 工具
# ============================================================

# ---------- 阶段 1: 构建 ----------
FROM golang:1.22-alpine AS builder

WORKDIR /build

# 安装编译依赖
RUN apk add --no-cache git ca-certificates tzdata

# 先复制 go.mod/go.sum 利用缓存
COPY go.mod go.sum ./
RUN go mod download

# 复制源码并编译
COPY . .

# 静态编译，不依赖外部 C 库
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s -X main.version=$(git describe --tags --always) \
    -X main.buildTime=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    -o /app ./cmd/server

# ---------- 阶段 2: 运行 ----------
FROM scratch

# 从构建阶段复制必要文件
COPY --from=builder /usr/share/zoneinfo/Asia/Shanghai /usr/share/zoneinfo/Asia/Shanghai
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app /app

# 环境变量
ENV TZ=Asia/Shanghai \
    GIN_MODE=release

# 暴露端口
EXPOSE 8080

# 入口
ENTRYPOINT ["/app"]
