# ============================================================
# Node.js 应用 Dockerfile
# 适用于 Express / NestJS / Next.js 应用
# ============================================================

# ---------- 阶段 1: 依赖安装 ----------
FROM node:20-alpine AS deps

WORKDIR /app

# 复制依赖文件
COPY package.json package-lock.json ./

# 安装生产依赖
RUN npm ci --only=production && \
    cp -R node_modules /prod_modules

# 安装全部依赖（含开发依赖，用于构建）
RUN npm ci

# ---------- 阶段 2: 构建 ----------
FROM node:20-alpine AS builder

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# 构建 TypeScript / Next.js 等
RUN npm run build

# ---------- 阶段 3: 运行 ----------
FROM node:20-alpine

# 安全：创建非 root 用户
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# 从构建阶段复制产物
COPY --from=deps /prod_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./

# 设置时区
RUN apk add --no-cache tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && apk del tzdata

# 环境变量
ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=1024"

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# 切换到非 root 用户
USER appuser

# 启动命令
CMD ["node", "dist/main.js"]
