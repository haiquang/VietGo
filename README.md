# VietGo — Bộ gõ Tiếng Việt Native cho macOS

**VietGo** là bộ gõ tiếng Việt mã nguồn sạch (clean-room) viết hoàn toàn bằng **Swift & SwiftUI** cho macOS (tối ưu cho Apple Silicon), kế thừa kinh nghiệm thực tế từ cộng đồng mã nguồn mở (`OpenKey`, `XKey`, `vi-rs`).

## Tính năng chính

- **Kiến trúc `CGEventTap` siêu nhẹ trên Menu Bar (`V` / `E`)**: Bỏ dấu trực tiếp bằng Unicode dựng sẵn (NFC), **loại bỏ hoàn toàn lỗi gạch chân** của bộ gõ mặc định macOS.
- **Hỗ trợ cả Telex và VNI**, bỏ dấu tự do trong âm tiết (`truongwf`, `truwowngf`, `duocdwj` → `trường`, `được`).
- **Tùy chọn quy tắc đặt dấu**:
  - **Dấu mới** (`hòa, khỏe, thủy, tùy`) — mặc định.
  - **Dấu cũ** (`hoà, khoẻ, thuỷ, tuỳ`).
- **Tự động khôi phục từ tiếng Anh / từ khóa code**: Phân tích âm vị học (`Onset + Nucleus + Coda + Tone`) để tự trả về nguyên bản các từ như `window`, `refresh`, `string`, `swift`, `text`, `next`, `left`, `port`, `tests`, `class`, `function`...
- **Chống lỗi lặp / nuốt chữ trên trình duyệt & Launcher**: Xử lý xung đột inline autocomplete trên Chrome, Safari, Arc, Brave, Edge, Firefox, Spotlight, Raycast, Alfred.
- **Phím tắt chuyển nhanh Việt / Anh**: Mặc định `⌃ Space` (Control + Space), hỗ trợ tùy chỉnh trực tiếp hoặc chọn nhanh (`⌃ Space`, `⌥ Z`, `⌘ ⇧`, `⌃ ⇧`).
- **An toàn mật khẩu**: Tự động ngắt xử lý khi con trỏ nằm trong ô mật khẩu (`IsSecureEventInputEnabled()`).

## Cấu trúc dự án

- `Sources/VietGoEngine/`: Lõi xử lý âm tiết tiếng Việt thuần Swift (không phụ thuộc AppKit/CGEvent):
  - `Models.swift` — Kiểu dữ liệu cấu hình & action.
  - `VietnameseTables.swift` — Bảng mã nguyên âm NFC, tập phụ âm đầu/cuối & vần hợp lệ.
  - `SyllableComposer.swift` — Bộ phân tích âm tiết, quy tắc `qu`/`gi`/`ươ`, dấu mới/cũ, double-key escape và kiểm tra âm vị học.
  - `VietInputEngine.swift` — Quản lý buffer từ hiện tại, tính toán LCP để tối thiểu số phím Backspace và đồng bộ khi nhấn Backspace giữa từ.
- `Sources/VietGoApp/`: Ứng dụng Menu Bar macOS (`AppSettings.swift`, `EventTapManager.swift`, `ShortcutRecorderView.swift`, `SettingsView.swift`, `VietGoApp.swift`).
- `Tests/VietGoEngineTests/`: Bộ unit test kiểm chứng Telex, VNI, dấu mới/cũ, tiếng Anh, giữ hoa/thường và Backspace.
- `scripts/build_app.sh`: Script biên dịch bản Release và đóng gói `dist/VietGo.app`.

## Cài đặt & Biên dịch

### Cách 1: Cài đặt qua Homebrew Cask (Khuyên dùng)

Cài đặt bằng Homebrew sẽ tự động gỡ cờ cách ly Gatekeeper để bạn mở ứng dụng trực tiếp mà không gặp hộp thoại chặn:

```bash
brew tap haiquang/vietgo https://github.com/haiquang/VietGo.git
brew trust haiquang/vietgo   # chỉ cần trên Homebrew 7+
brew install --cask haiquang/vietgo/vietgo
```

Cập nhật lên phiên bản mới sau này:

```bash
brew upgrade --cask haiquang/vietgo/vietgo
```

### Cách 2: Tải file `.dmg` từ GitHub Releases & Vượt macOS Gatekeeper

1. Tải `VietGo-v*-macos-arm64.dmg` mới nhất tại [GitHub Releases](https://github.com/haiquang/VietGo/releases/latest).
2. Mở file `.dmg` và kéo **VietGo.app** vào thư mục **Applications**.
3. **Mở lần đầu (vượt cảnh báo Gatekeeper):** Vì VietGo là phần mềm mã nguồn mở độc lập chưa trả phí ký chứng chỉ Apple Developer, macOS có thể hiện thông báo *"Apple could not verify “VietGo” is free of malware..."*. Hãy xử lý theo một trong hai cách sau:
   - **Cách A (Giao diện — macOS 15 Sequoia trở lên):** Bấm **Done** (tuyệt đối không bấm *Move to Trash*) → mở **System Settings → Privacy & Security** → cuộn xuống mục *Security* bấm **Open Anyway** → xác nhận mật khẩu hoặc Touch ID. *(Trên macOS 14 Sonoma: giữ `Control` + bấm chuột vào **VietGo** trong `/Applications` → chọn **Open**).*
   - **Cách B (Nhanh bằng 1 lệnh Terminal):**
     ```bash
     xattr -cr /Applications/VietGo.app
     open /Applications/VietGo.app
     ```

### Cách 3: Tự biên dịch từ mã nguồn

1. Chạy unit test:
   ```bash
   swift test
   ```
2. Biên dịch và đóng gói `.app`:
   ```bash
   bash scripts/build_app.sh
   ```
3. Cài đặt vào thư mục Applications và mở ứng dụng:
   ```bash
   cp -R dist/VietGo.app /Applications/
   open /Applications/VietGo.app
   ```

### Cấp quyền Trợ năng (Accessibility)

- Ở lần mở đầu tiên, bấm **Cấp quyền** trong cửa sổ cài đặt (hoặc vào *System Settings → Privacy & Security → Accessibility* và bật **VietGo**).
- Bộ gõ sẽ tự động kích hoạt ngay khi quyền được bật.

## Mẹo dùng phím tắt `Control + Space`

Nếu `⌃ Space` đang bị hệ thống macOS dùng để chuyển bộ gõ hệ thống (Input Source), bạn có thể tắt nó tại:
*System Settings → Keyboard → Keyboard Shortcuts… → Input Sources → bỏ chọn "Select the previous input source"*, hoặc chọn phím tắt khác như `⌥ Z` / `⌘ ⇧` trong Cài đặt của VietGo.

## Tùy biến quy tắc gõ

Bạn có thể chỉnh trực tiếp bảng âm đầu, âm cuối, vần hợp lệ trong `Sources/VietGoEngine/VietnameseTables.swift` hoặc logic ghép vần trong `Sources/VietGoEngine/SyllableComposer.swift`, sau đó chạy `swift test` và `bash scripts/build_app.sh` để cập nhật bản `.app`.

## Tài liệu & Các trường hợp xử lý

- **Hướng dẫn sử dụng, build & cài đặt đầy đủ:** [docs/GUIDE.md](docs/GUIDE.md)
- **Danh mục cấu trúc các trường hợp đã xử lý:** [docs/handled-cases/README.md](docs/handled-cases/README.md)
  - [01 — Ghép âm tiết Telex, VNI và các vần đặc biệt](docs/handled-cases/01-telex-vni-syllables.md)
  - [02 — Thoát dấu phím đúp và phân giải từ vựng](docs/handled-cases/02-escapes-and-disambiguation.md)
  - [03 — Khôi phục từ tiếng Anh, mã nguồn, từ rút gọn và URL](docs/handled-cases/03-english-code-and-urls.md)
  - [04 — Backspace, đồng bộ con trỏ và giới hạn hiệu năng](docs/handled-cases/04-backspace-and-editing.md)
  - [05 — Tương thích ứng dụng macOS & Tầng `CGEventTap`](docs/handled-cases/05-macos-apps-and-eventtap.md)

## Giấy phép

Copyright (c) 2026 VietGo Contributors

Dự án được phát hành theo giấy phép **GNU General Public License v3.0 (GPL-3.0)**. Xem chi tiết tại [LICENSE](LICENSE).


