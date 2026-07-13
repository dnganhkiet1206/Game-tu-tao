# HÒN GIÓ — Thiết kế kỹ thuật & Quyết định phạm vi

Tài liệu này ghi lại các quyết định của bản vertical slice theo góc nhìn technical lead:
chọn công nghệ gì, cắt gì, giữ gì, và mở rộng ra sao.

---

## 1. Vì sao chọn Godot 4.4?

| Tiêu chí | Godot 4 | Unity/Unreal |
|---|---|---|
| Export Android + iOS chính thức | ✅ | ✅ |
| Renderer riêng cho mobile (Vulkan, forward mobile) | ✅ `mobile` | Nặng hơn đáng kể |
| Project 100% text (script + scene) → review được, merge được, không asset nhị phân | ✅ | ❌ |
| Giấy phép | MIT, miễn phí | Ràng buộc |
| APK nhỏ | ~35–40 MB | 100 MB+ |

Với một slice cần *chứng minh công nghệ*, khả năng đọc-được-toàn-bộ-source và build nhẹ quan trọng hơn hệ sinh thái asset store.

## 2. Triết lý: mọi thứ sinh bằng code (procedural)

Không có file model/texture/audio ngoài — toàn bộ đảo, nhà cửa, nhân vật, xe, cây, đá và **38 hiệu ứng âm thanh** được sinh từ code:

- **Repo nhẹ**, không vấn đề bản quyền, ai clone cũng build được ngay.
- **Data-driven**: cả hòn đảo nằm trong `src/world/map_layout.gd` — thêm 1 dòng là có thêm 1 tòa nhà kèm nội thất, cửa, đèn, biển hiệu, va chạm.
- Đổi sang asset "xịn" sau này chỉ là thay tầng `Props`/`GameBuilding`/`Humanoid` — các hệ thống gameplay không phải sửa.

**Đánh đổi:** đồ họa là *stylized low-poly* chứ không đạt "semi-realistic" như yêu cầu gốc — semi-realistic cần team art thật sự (model, texture PBR, rig). Slice này ưu tiên: ánh sáng ngày/đêm đầy đủ, sương mù, bầu trời chuyển màu, mưa, đèn cửa sổ ban đêm — những thứ tạo "chất thương mại" mà không cần asset.

## 3. Kiến trúc

```
Autoload (singleton):
  Events    — signal bus; các hệ thống không gọi thẳng nhau
  Game      — tiền, kho đồ, sở hữu, thống kê, save/load JSON (user://)
  Audio     — pool 14 AudioStreamPlayer3D + 6 lớp ambience tự trộn theo vị trí
  DayNight  — 1 ngày = 24 phút thực; điều khiển mặt trời, sky, sương, thời tiết

Scene duy nhất main.tscn → src/main.gd dựng:
  WorldRoot (world_builder) → Terrain, GameBuilding×20, piers, props, RoadGraph
  PoliceManager, FishingController, TaxiJob, DeliveryJob
  NpcManager → NPC×22 + PoliceOfficer×2
  Vehicle×8, PlayerCharacter, CameraRig, Hud (menus, shop, joystick)
```

Điểm đáng chú ý:

- **Terrain**: hàm độ cao giải tích (noise + pad phẳng + lòng hồ + mỏ đá + bãi biển) → lưới 201×201; va chạm dùng **đúng tam giác của mesh hiển thị** (trimesh) nên không bao giờ lệch. Phân loại bề mặt mỗi đỉnh (cỏ/cát/đường/gỗ/đá) dùng cho **màu vertex** *và* **tiếng bước chân**.
- **NPC schedule**: máy trạng thái theo giờ (ngủ → sáng → làm → ăn trưa → làm → dạo chơi → ngủ), di chuyển bằng **A\* trên waypoint graph** sinh từ chính polyline đường — không cần bake navmesh. LOD: xa người chơi thì trượt không physics, khuất hẳn thì teleport.
- **Animation**: rig hộp 14 khớp + hàm pose thủ tục (đi/chạy/bơi/leo/chặt/đào/đấm/ngồi/câu), blend mượt 13 Hz — không cần file animation, NPC và player dùng chung.
- **Rà soát render**: mesh sinh code luôn kèm normal hướng ra ngoài + material 2 mặt → không bao giờ bị cull sai; mỗi tòa nhà 1 draw call; MultiMesh cho cây/đá/đèn.

## 4. Phạm vi đã chủ động cắt (và lý do)

| Yêu cầu gốc | Slice này | Lý do & đường mở rộng |
|---|---|---|
| Bản đồ ~1 km² | **800×800 m (0,64 km²)** | Mật độ > diện tích với demo 20–30 phút. Tăng `WORLD_SIZE` + thêm layout là mở rộng được. |
| 40–60 NPC | **24 NPC** | Giữ 30 FPS máy tầm trung; kiến trúc là data-table, thêm NPC = thêm dòng trong `npc_data.gd`. |
| Semi-realistic | **Stylized low-poly** | Xem mục 2. |
| Xe cộ giao thông tự chạy | **2 xe AI tuần tra** (phanh tránh chướng ngại, quay đầu cuối đường, cướp được) + 6 xe đỗ + 2 xe bán | Mạng đường là cây (không có vòng kín) nên xe chạy kiểu con thoi; giao lộ thông minh hơn là bước sau. |
| Cảnh sát lái xe truy đuổi | Truy đuổi **chạy bộ** + 3 mức sao | Đủ tạo vòng lặp phạm tội–hình phạt; xe cảnh sát là bước tiếp theo tự nhiên. |
| Lặn dưới nước | Chỉ **bơi trên mặt** | Lặn cần hệ oxy + camera nước; ít giá trị cho slice. |
| Minimap | **Có** — texture đảo bake 1 lần từ dữ liệu địa hình (201×201 px), cửa sổ zoom 250 m theo người chơi + mũi tên hướng + chấm mục tiêu; kèm mũi tên dẫn đường trên màn hình chính | Chi phí ~0 (1 texture nhỏ + vài lệnh draw 2D mỗi frame). |
| Đánh nhau đầy đủ | 1 đòn đấm + NPC bỏ chạy | Combat sâu không phải trọng tâm của IP đời-sống này. |
| Hệ đói/khát/máu | Chưa có (đồ ăn là flavor) | Tránh phình hệ thống; móc sẵn qua item `banh_mi`/`ca_phe`. |

## 5. Lộ trình phát triển tiếp (đề xuất theo thứ tự)

1. **Asset pass**: thay Props/Humanoid bằng model + texture thật (giữ nguyên interface) → đạt semi-realistic.
2. Xe cảnh sát truy đuổi + giao lộ/đèn tín hiệu cho xe AI (đã có 2 xe tuần tra nền).
3. Bản đồ toàn màn hình (minimap đã có; tái dùng cùng texture).
4. Chuỗi nhiệm vụ cốt truyện (hệ Events + objective đã sẵn sàng).
5. Hệ đói/năng lượng gắn vào đồ ăn hiện có.
6. Thú nuôi/câu hợp tác, thuyền (nước đã có ambience + bơi).
7. Đa ngôn ngữ (mọi chuỗi UI đang gom trong script — dời sang bảng translation).
8. Cloud save / nhiều slot save (`SAVE_VERSION` đã có trong JSON).

## 6. Ngân sách hiệu năng (mục tiêu: 60 FPS flagship / 30 FPS tầm trung)

- **Tam giác**: địa hình 160k (25 chunk, cull còn ~40k trên màn hình), nhà ~1–2k/căn, cây ~300/cây (MultiMesh).
- **Draw call trong thị trấn**: ~80–140 (nhà 2/căn, MultiMesh 5, terrain ~8–12, nhân vật ~15 mesh dùng chung material cache).
- **Đèn động**: mặt trời (+bóng đổ 2 split, 70 m) + tối đa ~6 OmniLight nội thất fade theo khoảng cách + 2 SpotLight đèn pha. Mức Thấp tắt hết trừ mặt trời.
- **Physics**: NPC xa tắt collision; xe đỗ tắt physics process; địa hình trimesh tĩnh 1 lần.
- **Âm thanh**: WAV 22 kHz mono, pool cố định — không cấp phát runtime.
- **Pin/RAM**: không texture lớn (vertex color), không particle dày (mưa 700 hạt), `max_fps=60`.

## 7. Kiểm định chất lượng trong môi trường phát triển

Project được phát triển trong môi trường không chạy được editor, nên:

- 100% file GDScript được kiểm qua **gdparse/gdlint** (parser chính thức của GDScript 4).
- Toàn bộ project được quét bằng **trình phân tích ngữ nghĩa Godot-faithful**
  (`@gdscript-analyzer/core`, chạy qua `node tools/analyze.mjs`) với đầy đủ
  autoload + cross-file resolution — hiện đạt **0 errors / 0 warnings** trên 37 file.
  Chính bước này đã bắt được một lỗi cú pháp lambda mà gdparse bỏ lọt.
- Các hợp đồng giữa hệ thống (tên hàm/tín hiệu/nhóm node) được rà soát chéo thủ công từng file.
- Những vùng rủi ro render (winding, cull) được phòng thủ bằng normal tường minh + material 2 mặt.

Nếu lần chạy đầu trong editor phát sinh lỗi runtime lặt vặt, chúng sẽ nằm ở tầng "wiring" (tên node/tham số) — kiến trúc và thuật toán đã được thiết kế để sửa các lỗi đó trong vài phút, không phải đập đi xây lại.
