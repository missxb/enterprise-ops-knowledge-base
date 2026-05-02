#============================================================================
# 企业级 Java 应用 Dockerfile（多阶段构建）
# 特性：多阶段构建、非 root 运行、健康检查、镜像优化
#============================================================================

#==================== Stage 1: 构建阶段 ====================
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# 先复制 pom.xml 利用 Docker 缓存
COPY pom.xml .
RUN mvn dependency:go-offline -B

# 复制源码并构建
COPY src ./src
RUN mvn clean package -DskipTests -B \
    && mv target/*.jar app.jar

#==================== Stage 2: 运行阶段 ====================
FROM eclipse-temurin:17-jre-alpine

# 安全：创建非 root 用户
RUN addgroup -g 1001 -S appgroup \
    && adduser -u 1001 -S appuser -G appgroup \
    && mkdir -p /app /app/config /app/logs /tmp \
    && chown -R appuser:appgroup /app /tmp

# 安装常用工具（生产可移除）
RUN apk add --no-cache \
    curl \
    tini \
    tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app

# 从构建阶段复制 JAR
COPY --from=builder /build/app.jar /app/app.jar

# JVM 优化参数
ENV JAVA_OPTS="-XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    -XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=75.0 \
    -XX:InitialRAMPercentage=50.0 \
    -Djava.security.egd=file:/dev/./urandom \
    -Dfile.encoding=UTF-8 \
    -Duser.timezone=Asia/Shanghai"

# 应用端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:8080/actuator/health || exit 1

# 切换到非 root 用户
USER appuser

# 使用 tini 作为 PID 1（正确处理信号）
ENTRYPOINT ["/sbin/tini", "--"]

# 启动命令
CMD ["sh", "-c", "java ${JAVA_OPTS} -jar /app/app.jar"]
