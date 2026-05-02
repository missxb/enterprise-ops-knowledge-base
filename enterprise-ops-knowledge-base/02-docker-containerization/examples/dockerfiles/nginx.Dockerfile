# ============================================================
# Nginx Dockerfile
# 适用于静态网站 / 反向代理
# ============================================================

FROM nginx:1.25-alpine

# 安全：移除默认页面
RUN rm -rf /usr/share/nginx/html/*

# 复制自定义配置
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# 复制静态资源（如有）
COPY dist/ /usr/share/nginx/html/

# 设置时区
RUN apk add --no-cache tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && apk del tzdata

# 创建缓存目录
RUN mkdir -p /var/cache/nginx/client_temp \
    && chown -R nginx:nginx /var/cache/nginx

# 暴露端口
EXPOSE 80 443

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1

# 启动
CMD ["nginx", "-g", "daemon off;"]
