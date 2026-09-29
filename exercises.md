# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder bằng câu trả lời của bạn.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Lê Đức Hùng  Mã học viên: 2A20260248

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Khi deploy lên Railway, mình quên paste biến `AGENT_API_KEY` vào dashboard
> (chỉ set `REDIS_URL` vì nghĩ Redis là quan trọng nhất). Nếu `agent_api_key`
> có default là `"changeme"` thì container vẫn build, vẫn "healthy" (vì
> `/health` không check key), vẫn trả 200 trên `/ready` — service trông xanh
> hoàn toàn trong dashboard Railway, và mình mất công debug chuyện khác.
> Nhờ không có default, uvicorn ném `ValidationError` ngay khi import
> `app.config`, container crash-loop, Railway báo `CrashLoopBackOff` trong
> vài giây → mình mở log thấy `Field required: agent_api_key` → fix trong
> 30 giây. Tóm lại: "không có key" phải fail ở boot, không phải ở request
> đầu tiên của user ngoài kia.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log thu được từ `utils.mock_llm` sau một request `/ask`:
>
> ```json
> {"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T05:42:11.183Z", "user_id": "sv-test", "tokens_in": 12, "tokens_out": 47, "cost_usd": 0.00018}
> ```
>
> Hai việc `print(...)` không làm được:
>
> 1. **Lọc/cảnh báo tự động.** Vì mỗi dòng là một JSON object trên một
>    dòng, mình có thể `jq 'select(.cost_usd > 0.001)'` để tìm mọi request
>    đắt tiền, hoặc dán thẳng vào Datadog/Loki để set alert
>    `cost_usd > 0.01`. Với `print()` mình phải `grep` chuỗi tự do và không
>    bao giờ parse được bằng máy một cách đáng tin.
> 2. **Đếm token theo user.** Dùng `jq '.tokens_in + .tokens_out' | group_by(.user_id)`
>    mình tính được tổng token/user trong một giờ — cơ sở để quyết định
>    tăng `rate_limit_per_minute` cho nhóm nào, hoặc cắt budget của nhóm
>    nào. Với `print("đã trả lời xong")` thì thông tin đó đã nằm ngoài
>    stdout rồi.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ~1.05 GB |
| Multi-stage | ~180 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Phần chênh ~870 MB đến từ những thứ chỉ cần khi *build*, không cần khi
> *chạy*:
>
> - **Compiler toolchain** — `gcc`, `g++`, `make`, `libc-dev`, `musl-dev`:
>   `pip` kéo về để biên dịch các package có wheel C như `pydantic`,
>   `cryptography`. Image multi-stage đã vứt đi sau khi `pip install` xong.
> - **Wheel & build artifacts** — `pip` lưu lại `.whl` đã tải (~200 MB),
>   và các file `.pyc`, `.so` của quá trình build tạm.
> - **Cache của trình quản lý gói** — `/var/lib/apt/lists/*` (~50 MB) chứa
>   metadata apt sau khi cài `build-essential`, không cần khi chạy.
>
> Runtime image của mình chỉ giữ `python:3.11-slim` + `/app/venv` đã
> hoàn chỉnh + source code, nên rơi vào ~180 MB. Số byte tiết kiệm đi thẳng
> vào thời gian `docker pull` khi Railway spin container mới (cold start
> giảm rõ rệt).

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Dockerfile của mình copy theo thứ tự `requirements.txt` → `pip install`
> → `COPY app/` → `COPY utils/`. Khi sửa một dòng trong `app/main.py`:
>
> - **Cache hit:** layer `COPY requirements.txt` (file không đổi), layer
>   `RUN python -m venv && pip install` (~25 giây) → bỏ qua hoàn toàn.
> - **Cache miss:** layer `COPY app/ ./app/` (hash của thư mục đổi vì có
>   file mới), kéo theo mọi layer phía sau nó. Chỉ mất vài giây nhưng
>   build vẫn phải chạy lại từ đây.
>
> Nếu đặt `COPY . .` lên trước `RUN pip install` thì ngược lại: sửa
> `main.py` đổi hash của `COPY . .`, **mọi layer sau đó đều bust cache**,
> kể cả `pip install`. Mỗi lần sửa code là phải `pip install` lại toàn bộ
> 26 package (25–40 giây). Vì lý do đó mà Dockerfile chuẩn luôn copy
> `requirements.txt` riêng và pip-install trước, source code copy sau.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Lấy ví dụ một dependency Python trong `requirements.txt` có CVE cho phép
> chèn path traversal khi parse một file upload. Trong app mình, endpoint
> `/ask` không nhận file, nhưng có dependency `pydantic` có thể bị trigger
> qua input JSON sâu nhiều cấp (CVE kiểu ReDoS hoặc arbitrary code qua
> validator tùy biến).
>
> Chuỗi sự kiện nếu chạy root:
>
> 1. Attacker gửi payload kích hoạt lỗi trong library.
> 2. Code độc hại chạy **bên trong process uvicorn với UID 0** — root trong
>    container, mà container trong Linux dùng chung kernel với host.
> 3. Payload gọi `subprocess` chạy `chroot /host` hoặc mount `/proc` của
>    host, đọc `/proc/1/root/etc/shadow`, hoặc cài `cron job` vào
>    `/var/spool/cron/` của host.
> 4. Nếu host có Docker socket bind ra (`/var/run/docker.sock`), attacker
>    chạy `docker run --privileged ...` → root toàn bộ máy.
>
> Lệnh `USER appuser` trong Dockerfile cắt đứt tại bước 2: dù code chạy
> được, nó chỉ có quyền của UID 1000 trong container, không có CAP_SYS_ADMIN,
> không mount được `/proc`, không ghi được vào `/etc`. Container có bị
> compromise thì attacker chỉ thấy được `/app` và `venv` — không thoát ra
> host. Đây là lý do Dockerfile mình có cả `groupadd` + `useradd` rồi
> `USER appuser` cuối stage 2.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> **20 request trong 2 giây.** Cách làm: đợi tới giây 59 của phút N, gửi
> 10 request liên tiếp → đều nằm trong phút N, đếm đủ 10 nhưng "phút đồng
> hồ" chưa reset. Sang giây 00 của phút N+1, counter về 0, gửi tiếp 10
> request nữa. Hai phút N và N+1 đều "hợp lệ" từng phút một, nhưng thực
> tế server vừa xử lý 20 request cách nhau vài trăm mili-giây.
>
> Sliding window trong `rate_limiter.py` (Redis ZSET, score = timestamp)
> tránh được đúng kịch bản này: trước khi ghi nhận request mới nó
> `ZREMRANGEBYSCORE key 0 now-60`, rồi `ZCARD` — nghĩa là "đếm lại trong
> 60 giây **gần nhất tính từ bây giờ**", không quan tâm phút đồng hồ là
> mấy. Cùng 20 request ở trên sẽ vi phạm ngay request thứ 11 ở giây 00.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Rate limit đếm **số lần gọi** (request), cost guard đếm **số tiền đã
> đốt** (USD từ token). Rate limit chặn theo `429 Too Many Requests`, cost
> guard chặn theo `402 Payment Required`.
>
> **Rate limit cho qua, cost guard chặn:** User gửi 5 câu hỏi ngắn trong
> một phút — rate limit (10/phút) hoàn toàn OK, nhưng trong ngày đó họ đã
> hỏi các prompt rất dài (mỗi prompt ~50k input token), cộng dồn đã
> vượt `monthly_budget_usd = 10`. Request thứ 6 trong phút đó pass qua
> `RateLimiter.check` nhưng `CostGuard.check` throw 402 vì `spent + est >
> budget`. Rate limit không hề hay biết có bao nhiêu token trong mỗi
> request.
>
> **Cost guard cho qua, rate limit chặn:** Một user mới tinh, chưa tốn đồng
> nào, cost guard thấy `spent ≈ 0 < 10 USD`. Nhưng họ spam 12 request
> trong 30 giây đầu — request thứ 11 bị `RateLimiter.check` ném 429 vì
> ZSET đã có 10 timestamp trong 60 giây gần nhất. Cost guard không có cớ
> gì để chặn vì tiền vẫn chưa vượt budget.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Thứ tự sự kiện nếu `GET /health` cũng `store.ping()` luôn:
>
> 1. Redis mất kết nối (network blip, hoặc Redis restart). Tới giây thứ 1,
>    cả 3 container cùng không ping được Redis.
> 2. Cả 3 container bắt đầu trả **503** từ `/health`. Theo healthcheck của
>    Railway/Docker, mỗi container thất bại 1 lần, không đủ để bị kill
>    (mặc định `--retries=3`), nhưng **Railway load balancer / Docker
>    replica controller coi như cả cụm down** và ngừng đẩy traffic vào.
> 3. Trong lúc đó, các request `/ask` cũ còn nằm trong hàng đợi của
> uvicorn trả lỗi 502/503 vì Redis không có sẵn — không có cái gì chạy
>    được cả.
> 4. Tới giây thứ 5, container đầu fail đủ `--retries=3` lần liên tiếp
>    trong healthcheck, Docker restart container. Container khởi động
>    lại, vẫn không có Redis → tiếp tục fail healthcheck → restart vô
>    hạn → **CrashLoopBackOff**. Cả 3 container đều đi vào vòng lặp
>    này.
> 5. Redis quay lại ở giây 30, nhưng cả cụm mất thêm 1–2 phút để ổn định
>    trở lại, vì mỗi container phải vượt qua `start-period` của
>    healthcheck rồi mới được nhận traffic.
>
> Vì `/health` hiện tại **chỉ check `lifecycle.shutting_down`** (không
> chạm Redis), khi Redis chết container vẫn 200, không bị kill oan.
> `/ready` mới là cái trả 503 trong tình huống này, và load balancer
> đẩy traffic sang container còn sống. Khi Redis hồi, `/ready` trở lại
> 200 và cluster tự cân bằng lại trong vài giây, không cần restart
> container nào.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Khi scale `agent=3`, cùng một user với cùng `X-User-Id` được load balancer
> phân vào **3 process khác nhau** qua các lần gọi. Lịch sử lưu trong
> Redis (`history:{user_id}` list, append bằng `RPUSH`), cả 3 container
> cùng nhìn thấy một danh sách. Kết quả: `history_length` tăng đều qua
> mỗi lần gọi (0 → 2 → 4 → 6...) bất kể request rơi vào container nào,
> vì `get_history` đọc từ Redis trước khi LLM sinh câu trả lời.
>
> Nếu lưu trong `dict` Python của mỗi process: container A có
> `self._history[user] = [...]` riêng, container B có bản riêng, container
> C cũng vậy. Cùng một user, gọi `/ask` lần 1 vào A (length = 0), lần 2
> vào B (length = 0 vì B chưa từng thấy user này), lần 3 vào C (length = 0).
> Con số dao động giữa 0 và 2 thay vì tăng tuyến tính — và tệ hơn, agent
> "mất trí nhớ" mỗi khi round-robin chuyển container. Thêm nữa: container
> A restart vì deploy → mất sạch dict trong RAM → mất trí nhớ hoàn toàn
> dù không có lỗi gì.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> Lỗi thật của mình: `pytest tests/test_cp5.py -v` báo **4/4 test public
> deployment FAIL**, mặc dù service trên Railway trả 200 hoàn toàn bình
> thường. Curl thẳng vào URL Railway thì `/health` 200, `/ready` 200, mọi
> thứ xanh — nhưng test thì gọi URL đó lại fail với `ConnectionError` /
> `404 Application not found`.
>
> Cách mình tìm ra: mở `tests/test_cp5.py` thấy test parse URL từ
> `DEPLOYMENT.md` bằng regex. Soi lại file đó thì thấy dòng 21 đang ghi
> `https://day12-agent-2a20260248.up.railway.app` — URL cũ mình điền từ
> lần deploy đầu, **subdomain `day12-agent-2a20260248` không tồn tại
> trên Railway** (Railway tự sinh subdomain kiểu
> `<repo-name>-production.up.railway.app`, không phải `<tên-tùy-ý>`).
> Test gọi vào URL ma → 404 → test fail dù service thật vẫn chạy ngon.
>
> Cách sửa: lấy URL thật từ dashboard Railway (mục "Settings → Domains"),
> copy `<repo-slug>-production.up.railway.app` rồi dán lại vào
> `DEPLOYMENT.md`. Đồng thời đổi `LOCAL_FALLBACK=true` thành `false`
> trong `.env` để test chạy thật (chứ không chạy nhánh fallback nữa).
> Re-run `pytest tests/test_cp5.py -v` → 8 passed, 4 critical public
> deployment tests xanh. Bài học: URL trong tài liệu là một phần test
> fixture, sai URL là fail test — không phải lỗi deploy.
