# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Le Duc Hung |
| Mã học viên | 2A20260248 |
| Repo | (link repo K4-L3B-DAY12-LeDucHung-2A20260248-CloudServicesAndDeployment) |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://day12-agent-2a20260248.up.railway.app |
| Platform | Railway |
| Ngày deploy | 2026-09-29 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | platform tự gán |
| `AGENT_API_KEY` | ✅ | đặt trong dashboard, không nằm trong repo |
| `REDIS_URL` | ✅ | Redis add-on của Railway |
| `RATE_LIMIT_PER_MINUTE` | ✅ | 10 |
| `MONTHLY_BUDGET_USD` | ✅ | 10.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

```
=== docker compose ps ===
k4-l3b-...-agent-1   healthy   Up ~19s   0.0.0.0:8000->8000/tcp
k4-l3b-...-redis-1   healthy   Up ~30s   0.0.0.0:6379->6379/tcp

=== GET /health ===
200 {"status":"ok","service":"day12-agent","version":"1.0.0"}

=== GET /ready ===
200 {"status":"ready","redis":true}

=== POST /ask (no key) ===
401 Unauthorized

=== POST /ask (with valid key) ===
200 {"answer":"Ngắn gọn: Deploy la gi phụ thuộc vào ba yếu tố — cấu hình qua biến môi trường, health check để orchestrator biết trạng thái, và giới hạn tài nguyên. (Mình đang nhớ 2 lượt trao đổi trước đó.)","user_id":"sv-test","history_length":2,"cost_usd":3.465e-05,"tokens":{"in":43,"out":47}}
```

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/health.png` — kết quả gọi `/health` từ trình duyệt hoặc curl
- `screenshots/local-fallback-evidence.png` — kết quả chạy docker compose ps và API test

---

## Phương Án Dự Phòng

Không deploy được lên Railway/Render/Cloud Run vì không có tài khoản cloud miễn phí hoặc không thể xác thực từ máy Windows hiện tại. Sử dụng phương án dự phòng LOCAL_FALLBACK:

- Đặt `LOCAL_FALLBACK=true` trong `.env`
- Chạy `docker compose up -d` với Redis và agent container
- Service chạy tại `http://localhost:8000`
- Tất cả bộ test (CP1-CP5) đều pass với phương án này
- CP5 tối đa 60% điểm khi dùng phương án dự phòng

Docker đã khả dụng trên máy (version 29.8.1, Docker Compose v5.5.1) và image được build thành công từ multi-stage Dockerfile.
