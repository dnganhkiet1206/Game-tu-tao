# 🏝 HÒN GIÓ — Open-World Mobile Vertical Slice

**Hòn Gió** là một bản demo (vertical slice) game thế giới mở trên điện thoại: bạn sống trên một hòn đảo ven biển Việt Nam, kiếm tiền bằng 5 nghề (câu cá, chặt gỗ, đào quặng, taxi, giao hàng), mua xe, nâng cấp nhà — trong một thị trấn nhỏ có ~24 cư dân sinh hoạt theo lịch ngày/đêm và một hệ thống cảnh sát đơn giản.

Đây là **IP hoàn toàn mới**, chỉ lấy cảm hứng "thế giới mở trên mobile" — không phải GTA.

> 📐 Các quyết định kiến trúc, phạm vi đã cắt giảm và lộ trình mở rộng: xem [DESIGN.md](DESIGN.md).

---

## 1. Yêu cầu

| Thành phần | Phiên bản |
|---|---|
| **Godot Engine** | **4.4.x** (bản chuẩn, không cần .NET) — tải tại https://godotengine.org/download |
| Android build | Android SDK + Java 17 + Export Templates (hướng dẫn bên dưới) |
| iOS build | macOS + Xcode + tài khoản Apple Developer |

Toàn bộ project là **text + asset sinh tự động** — không có asset nhị phân bên ngoài, không vấn đề bản quyền.

## 2. Chạy thử ngay trên máy tính (khuyên làm trước)

1. Mở **Godot 4.4** → `Import` → chọn file `project.godot` của repo này.
2. Lần đầu mở, Godot sẽ import ~38 file âm thanh (vài giây).
3. Nhấn **F5** (Run Project).

Điều khiển trên PC (để test): **WASD** di chuyển, **Space** nhảy/leo, **Shift** chạy nhanh, **E** tương tác, **F** đấm, **H** còi xe, chuột kéo (giữ chuột phải/trái ở nửa phải màn hình) xoay camera, **Esc** tạm dừng. Chuột cũng giả lập cảm ứng nên joystick ảo hoạt động khi kéo ở nửa trái màn hình.

## 3. Build & cài lên điện thoại Android

Chỉ cần làm 1 lần:

1. Trong Godot: `Editor → Manage Export Templates → Download and Install`.
2. Cài **Android Studio** (hoặc chỉ SDK command-line tools) + **Java 17**.
3. Trong Godot: `Editor → Editor Settings → Export → Android` — điền đường dẫn `Android SDK Path` và `Debug Keystore` (Godot tự tạo debug keystore nếu bấm nút bên cạnh).

Build:

4. `Project → Export…` → chọn preset **Android** (đã cấu hình sẵn trong repo: arm64-v8a, landscape, immersive).
5. Bấm **Export Project** → chọn nơi lưu `HonGio.apk` (giữ "Debug" cho nhanh).
6. Chép APK vào máy và cài, hoặc cắm cáp USB bật USB debugging rồi bấm nút **▶ (Remote Deploy)** ngay trên toolbar Godot — game cài và chạy thẳng trên điện thoại.

> Tài liệu chính thức nếu vướng: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html

## 4. Build iOS (cần máy Mac)

1. `Project → Export…` → preset **iOS** → điền `App Store Team ID` + Bundle ID của bạn.
2. **Export Project** → mở file `.xcodeproj` sinh ra bằng Xcode → chọn signing team → Run lên iPhone.

> Tài liệu: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html

## 5. Điều khiển trên điện thoại

| Vùng màn hình | Chức năng |
|---|---|
| Góc trên trái | **Minimap** theo người chơi (mũi tên = hướng, chấm vàng = mục tiêu) — **chạm vào để mở bản đồ toàn đảo** với icon cửa hàng 🏪, gara 🚗, cảnh sát 🚓, chợ cá 🐟, điểm câu 🎣… (phím M trên PC) |
| Nửa **trái** | Joystick ảo nổi (chạm đâu cần hiện đó) |
| Nửa **phải** (vuốt) | Xoay camera |
| Nút **❗/✋** | Tương tác theo ngữ cảnh (mở cửa, nói chuyện, mua bán, câu cá, lên xe…) |
| Nút **⬆** | Nhảy / leo lên vật cản, gờ tường |
| Nút **🏃** | Bật/tắt chạy nhanh |
| Nút **👊** | Đấm (cẩn thận, cảnh sát sẽ truy nã!) |
| Trong xe | **▲** ga, **▼** phanh/lùi, **🅿** phanh tay, **📢** còi, **🚪** ra xe |

## 6. Chơi như thế nào?

- Bạn bắt đầu trước cửa **nhà riêng** với 150₫ và một **cần câu**.
- **Câu cá** 🎣 ở cầu tàu biển/hồ → bán ở **Chợ Cá Bến Sóng**.
- Mua **rìu / cuốc chim** ở **Tạp hoá Cô Ba** → **chặt gỗ** trong rừng (bán ở Xưởng Gỗ), **đào quặng** ở mỏ đá phía đông nam (bán ở Trạm Thu Quặng — quặng vàng rất hiếm và đắt).
- Lên chiếc **taxi vàng** ở quảng trường → chở khách theo mũi tên, chạy nhanh có tip.
- Nhận **giao hàng** 📦 trước cửa tạp hoá → giao 3 kiện tới các nhà dân, đủ nhanh có thưởng.
- Tiền dùng để: mua **ô tô** ở Gara Chú Tư, **nâng cấp nội thất nhà** (3 cấp), mua đồ ăn.
- **Ngủ trên giường nhà bạn** (sau 19:00) để lưu game và sang ngày mới. Lưu thủ công trong menu tạm dừng.
- Đánh người / cướp xe / **đập phá xe dân** → bị **truy nã ⭐**: chạy trốn đủ lâu, hoặc đến trạm cảnh sát nộp phạt; bị bắt thì mất tiền phạt.
- NPC có lịch sinh hoạt thật: ngủ ở nhà, sáng đi làm, trưa ăn quán, tối dạo quảng trường/bãi biển.
- Có **xe cộ chạy trên đường** (biết phanh tránh người) — và bạn có thể… chặn đầu cướp luôn chiếc xe đang chạy 😏.
- **Xe tốn xăng** ⛽: đồng hồ xăng hiện khi lái, sắp cạn có bíp cảnh báo, hết xăng là chết máy giữa đường. Đổ xăng ở **Trạm Xăng Hòn Gió** (2₫/L, lái xe vào trụ bơm), hoặc mua **can xăng 10L** để cứu hộ. Taxi và xe mua ở gara có sẵn một can dự phòng — **mở cốp xe** ra mà lấy!

## 7. Cấu trúc project

```
project.godot            # cấu hình (mobile renderer, autoload, input map)
export_presets.cfg       # preset xuất Android / iOS có sẵn
scenes/main.tscn         # scene duy nhất — mọi thứ dựng bằng code
assets/audio/            # 38 file WAV sinh bằng tools/generate_audio.py
tools/generate_audio.py  # bộ tổng hợp âm thanh (python3 + numpy)
src/
  core/                  # autoload: events (signal bus), game_state (save/load),
                         # audio_manager (SFX + ambience), day_night, layers
  world/                 # map_layout (dữ liệu đảo), terrain, building, props,
                         # palette (materials), road_graph, weather, world_builder
  characters/            # humanoid (rig + animation thủ tục), player, camera_rig,
                         # npc, npc_data, npc_manager, police_officer
  vehicles/              # vehicle.gd (xe arcade + cửa + âm thanh)
  jobs/                  # fishing, taxi_job, delivery_job, resource_node, item_pickup
  police/                # police_manager (hệ thống truy nã)
  ui/                    # hud, virtual_joystick, touch_button, shop_panel, menus
```

## 8. Hiệu năng trên mobile

- Renderer **Mobile (Vulkan)**, texture nén ETC2/ASTC, tối đa 60 FPS.
- Địa hình chia 25 chunk để cull; mỗi tòa nhà gộp thành **1 draw call**; cây/đá/cột đèn dùng **MultiMesh**.
- NPC có LOD: gần người chơi mới bật physics, ở xa trượt trên waypoint (gần như miễn phí).
- 3 mức **Đồ hoạ** trong menu (Thấp / Vừa / Cao): đổi độ phân giải render, bóng đổ, đèn nội thất.
- Máy tầm trung nên để **Vừa**; máy yếu để **Thấp** (tắt bóng đổ, render scale 0.8).

## 9. Công cụ dev (tuỳ chọn)

```bash
# Tái tạo toàn bộ âm thanh
pip install numpy
python3 tools/generate_audio.py

# Phân tích ngữ nghĩa toàn bộ GDScript (trình phân tích chuẩn Godot 4, chạy bằng Node)
npm i @gdscript-analyzer/core
node tools/analyze.mjs            # mục tiêu: 0 errors, 0 warnings
```

## 10. Giấy phép

Toàn bộ code và asset trong repo được sinh riêng cho project này — bạn toàn quyền sử dụng.
