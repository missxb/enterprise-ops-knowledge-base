#!/usr/bin/env python3
"""
Locust 分布式压测脚本
用途: API 接口性能测试、Web 应用负载测试
特点: 支持分布式、实时 Web UI、自定义场景
"""

from locust import HttpUser, task, between, events
from locust.runners import MasterRunner, WorkerRunner
import json
import time
import logging
import csv
import os
from datetime import datetime

# 日志配置
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("loadtest")


# ==================== 测试数据准备 ====================
class TestData:
    """测试数据管理"""

    def __init__(self):
        self.users = []
        self.tokens = []
        self._load_data()

    def _load_data(self):
        """加载测试数据"""
        data_file = os.environ.get("TEST_DATA_FILE", "test_data.json")
        if os.path.exists(data_file):
            with open(data_file) as f:
                data = json.load(f)
                self.users = data.get("users", [])
                self.tokens = data.get("tokens", [])
        else:
            # 默认测试数据
            self.users = [{"username": f"user{i}", "password": "Test123456"} for i in range(1, 101)]

    def get_user(self, index):
        return self.users[index % len(self.users)]

    def get_token(self, index):
        return self.tokens[index % len(self.tokens)] if self.tokens else None


test_data = TestData()


# ==================== 事件钩子 ====================
@events.init.add_listener
def on_init(environment, **kwargs):
    """初始化事件"""
    if isinstance(environment.runner, MasterRunner):
        logger.info("🎯 Master 节点启动")
    elif isinstance(environment.runner, WorkerRunner):
        logger.info("🔧 Worker 节点启动")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """测试开始"""
    logger.info(f"🚀 压测开始 - 时间: {datetime.now()}")
    logger.info(f"   目标: {environment.host}")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """测试结束"""
    logger.info(f"✅ 压测结束 - 时间: {datetime.now()}")


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response, exception, **kwargs):
    """请求事件 - 记录慢请求"""
    if response_time > 3000:  # 超过3秒的请求
        logger.warning(f"🐌 慢请求: {name} - {response_time}ms")
    if exception:
        logger.error(f"❌ 请求失败: {name} - {exception}")


# ==================== 用户行为定义 ====================
class WebsiteUser(HttpUser):
    """Web 用户行为模拟"""

    wait_time = between(1, 3)  # 请求间隔 1-3 秒
    host = "http://localhost:8080"

    def on_start(self):
        """用户启动时执行 - 登录"""
        self.token = None
        self.user_id = None
        self._login()

    def _login(self):
        """模拟登录"""
        user_data = test_data.get_user(0)
        with self.client.post(
            "/api/v1/auth/login",
            json=user_data,
            name="登录",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    self.token = data.get("token", "")
                    self.user_id = data.get("user_id", "")
                    response.success()
                except json.JSONDecodeError:
                    response.failure("响应不是有效 JSON")
            else:
                response.failure(f"登录失败: {response.status_code}")

    def _get_headers(self):
        """获取认证头"""
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    # ---- 核心业务场景 ----

    @task(10)
    def browse_homepage(self):
        """浏览首页 (高频)"""
        self.client.get("/", name="首页", headers=self._get_headers())

    @task(8)
    def search_items(self):
        """搜索商品 (高频)"""
        params = {"keyword": "test", "page": 1, "size": 20}
        self.client.get(
            "/api/v1/items/search",
            params=params,
            name="搜索商品",
            headers=self._get_headers()
        )

    @task(6)
    def get_item_detail(self):
        """查看商品详情 (中频)"""
        item_id = 1001
        self.client.get(
            f"/api/v1/items/{item_id}",
            name="商品详情",
            headers=self._get_headers()
        )

    @task(4)
    def get_user_profile(self):
        """获取用户信息 (中频)"""
        if self.user_id:
            self.client.get(
                f"/api/v1/users/{self.user_id}",
                name="用户信息",
                headers=self._get_headers()
            )

    @task(3)
    def create_order(self):
        """创建订单 (低频)"""
        order_data = {
            "items": [{"item_id": 1001, "quantity": 1}],
            "address_id": 1,
            "payment_method": "alipay"
        }
        self.client.post(
            "/api/v1/orders",
            json=order_data,
            name="创建订单",
            headers=self._get_headers()
        )

    @task(2)
    def get_order_list(self):
        """查询订单列表 (低频)"""
        self.client.get(
            "/api/v1/orders",
            params={"page": 1, "size": 10},
            name="订单列表",
            headers=self._get_headers()
        )

    @task(1)
    def health_check(self):
        """健康检查 (最低频)"""
        self.client.get("/health", name="健康检查")


class APIUser(HttpUser):
    """API 接口压测 - 更高并发"""

    wait_time = between(0.5, 1.5)
    host = "http://localhost:8080"

    @task(5)
    def api_list(self):
        """API 列表接口"""
        self.client.get("/api/v1/items", name="API-列表")

    @task(3)
    def api_detail(self):
        """API 详情接口"""
        self.client.get("/api/v1/items/1001", name="API-详情")

    @task(2)
    def api_create(self):
        """API 创建接口"""
        data = {"name": "test", "price": 99.99, "category": "test"}
        self.client.post("/api/v1/items", json=data, name="API-创建")

    @task(1)
    def api_batch(self):
        """API 批量接口"""
        data = {"ids": list(range(1001, 1021))}
        self.client.post("/api/v1/items/batch", json=data, name="API-批量查询")


class StressTestUser(HttpUser):
    """压力测试用户 - 模拟极端场景"""

    wait_time = between(0.1, 0.5)  # 极短间隔
    host = "http://localhost:8080"

    @task
    def rapid_requests(self):
        """快速连续请求"""
        self.client.get("/api/v1/items", name="快速请求")

    @task
    def large_payload(self):
        """大请求体"""
        data = {"items": [{"id": i, "name": f"item_{i}"} for i in range(100)]}
        self.client.post("/api/v1/items/batch", json=data, name="大请求体")

    @task
    def concurrent_write(self):
        """并发写入"""
        data = {"name": f"stress_{int(time.time())}", "price": 1.0}
        self.client.post("/api/v1/items", json=data, name="并发写入")


# ==================== 自定义统计 ====================
class StatsCollector:
    """统计收集器"""

    def __init__(self):
        self.results = []
        self.start_time = None

    def start(self):
        self.start_time = time.time()

    def record(self, name, response_time, status):
        self.results.append({
            "name": name,
            "response_time": response_time,
            "status": status,
            "timestamp": time.time()
        })

    def summary(self):
        if not self.results:
            return "无数据"

        total = len(self.results)
        success = sum(1 for r in self.results if r["status"] == "success")
        fail = total - success
        avg_rt = sum(r["response_time"] for r in self.results) / total
        max_rt = max(r["response_time"] for r in self.results)
        min_rt = min(r["response_time"] for r in self.results)

        return f"""
压测统计:
  总请求: {total}
  成功: {success}
  失败: {fail}
  平均RT: {avg_rt:.0f}ms
  最大RT: {max_rt:.0f}ms
  最小RT: {min_rt:.0f}ms
"""
