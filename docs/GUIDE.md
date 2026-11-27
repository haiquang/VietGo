# Hướng dẫn sử dụng và phát triển VietGo

**VietGo** là bộ gõ tiếng Việt native trên macOS viết bằng Swift và SwiftUI. Ứng dụng xử lý bỏ dấu trực tiếp bằng Unicode dựng sẵn (NFC) ở tầng `CGEventTap` để loại bỏ hoàn toàn dấu gạch chân khi gõ nhanh trên trình duyệt, IDE và terminal.

---

## 1. Tổng quan & Kiến trúc

VietGo tách biệt thành hai module chính:

- **`VietGoEngine` (`Sources/VietGoEngine/`)**: Lõi xử lý âm tiết tiếng Việt thuần Swift, không phụ thuộc `AppKit` hay `CGEvent`:
  - `Models.swift`: Định nghĩa kiểu dữ liệu `EngineConfig`, `EngineAction`, `InputMethod`, `ToneStyle`, `Tone`, `VowelShape`.
  - `VietnameseTables.swift`: Chứa bảng mã nguyên âm NFC (`decodeVowel`, `vowelCharacter`), danh sách `validOnsets`, `validCodas`, `validOpenNuclei`, `validClosedNuclei`, `intermediateOnlyNuclei`, `englishNonWordExceptions` và hàm `canonicalRawKeys`.
  - `SyllableComposer.swift`: Phân tích cấu trúc `Onset + Nucleus + Coda + Tone`, xử lý bỏ dấu tự do, chuyển đổi `uô ↔ ươ`, double-key escape và kiểm tra âm vị học (`isPhonotacticallyValid`, `isValidEnglishWord`).
  - `VietInputEngine.swift`: Máy trạng thái cấp từ/câu, quản lý `committedHistory`, tính toán tiền tố chung dài nhất (LCP) để giảm số phím Backspace, bảo vệ URL/đường dẫn và khôi phục từ rút gọn tiếng Anh.
- **`VietGoApp` (`Sources/VietGoApp/`)**: Ứng dụng Menu Bar (`V` / `E`), giao diện cài đặt 4 tab (`SettingsView.swift`, `DesignComponents.swift`, `ShortcutRecorderView.swift`, `AppSettings.swift`) và tầng bắt/bơm phím hệ thống (`EventTapManager.swift`).

Luồng xử lý phím bấm:

1. `EventTapManager` mở event tap ở tầng `.cghidEventTap` (fallback sang `.cgSessionEventTap` nếu cần).
2. Khi người dùng gõ phím, sự kiện đi qua `VietInputEngine.processKey(_:)` hoặc `handleBackspace()`.
3. Nếu cần thay thế ký tự, `injectReplacement` tuần tự hóa qua `injectionSemaphore`, gửi Backspace và chèn chuỗi Unicode NFC bằng `tapPostEvent(proxy)` với `CGEventSource(stateID: .privateState)` nhằm giữ đúng thứ tự sự kiện khi gõ lướt tốc độ cao.

---

## 2. Yêu cầu, Build & Cài đặt

### Chạy unit test

```bash
swift test
```

Lệnh này chạy toàn bộ unit test trong `Tests/VietGoEngineTests/VietGoEngineTests.swift`.

### Cài đặt nhanh qua Homebrew Cask (Khuyên dùng)

```bash
brew tap haiquang/vietgo https://github.com/haiquang/VietGo.git
brew trust haiquang/vietgo   # chỉ cần trên Homebrew 7+
brew install --cask haiquang/vietgo/vietgo
```

Cask trong kho mã (`Casks/vietgo.rb`) tự động gỡ cờ cách ly Gatekeeper (`com.apple.quarantine`) sau khi cài.

### Build và đóng gói `.app`

```bash
bash scripts/build_app.sh
```

Script sẽ biên dịch bản release, tạo icon (nếu chưa có `Resources/AppIcon.icns`), đóng gói bundle tại `dist/VietGo.app` và ký chữ ký số.

### Cài đặt thủ công từ `.dmg` hoặc bản build & Vượt macOS Gatekeeper

```bash
cp -R dist/VietGo.app /Applications/
open /Applications/VietGo.app
```

Nếu tải `VietGo-v*-macos-arm64.dmg` từ trình duyệt, macOS Gatekeeper sẽ báo cảnh báo ứng dụng chưa qua notarization của Apple khi mở lần đầu:

- **macOS 15 Sequoia trở lên:** Bấm **Done** (không bấm *Move to Trash*) → mở **System Settings → Privacy & Security** → cuộn xuống bấm **Open Anyway**.
- **macOS 14 Sonoma:** Giữ `Control` + bấm vào **VietGo** trong `/Applications` → chọn **Open**.
- **Hoặc dùng 1 lệnh Terminal:** `xattr -cr /Applications/VietGo.app && open /Applications/VietGo.app`.

### Cấp quyền Trợ năng (Accessibility)

1. Mở **System Settings → Privacy & Security → Accessibility**.
2. Bật công tắc cho **VietGo**. Nếu vừa cập nhật bản build mới dùng chữ ký ad-hoc (`-`), bạn cần tắt rồi bật lại quyền cho VietGo hoặc xóa mục cũ rồi thêm lại.

### Mẹo giữ quyền Accessibility khi tự build lại nhiều lần

Mặc định khi máy chưa có chứng chỉ ký mã, `scripts/build_app.sh` ký bằng ad-hoc (`-`), làm đổi `cdhash` sau mỗi lần build lại. Bạn có thể tạo một chứng chỉ tự ký cục bộ trong **Keychain Access**:

1. Mở **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Đặt tên chính xác là `VietGo Local CodeSign`, Identity Type: `Self Signed Root`, Certificate Type: `Code Signing`.
3. Chạy lại `bash scripts/build_app.sh`. Script tự động phát hiện và ký bằng `VietGo Local CodeSign` để macOS giữ nguyên quyền Accessibility qua các lần build tiếp theo.

---

## 3. Hướng dẫn cấu hình giao diện 4 tab

Cửa sổ cài đặt VietGo (`620 × 520` pt) gồm 4 tab chính:

### Tab `Bộ gõ`

- **Kiểu gõ**: Chọn giữa **Telex** (mặc định) và **VNI**.
- **Quy tắc đặt dấu**:
  - **Dấu mới** (mặc định): `` `hòa, khỏe, thủy, tùy` ``.
  - **Dấu cũ**: `` `hoà, khoẻ, thuỷ, tuỳ` ``.
- **Gõ `w` đơn thành `ư`**: Khi bật (mặc định), gõ `nhw` cho ra `như`, `wf` cho ra `ừ`. Các tiền tố đường dẫn như `~/w`, `foo/w`, `a.w` vẫn được giữ nguyên.
- **Gõ tắt `[` → `ơ`, `]` → `ư` trong Telex**: Hỗ trợ người quen bố cục phím tắt mở rộng (`h[` → `hơ`, `h]` → `hư`; gõ đúp `[[` hoặc `]]` để thoát về ký tự gốc).

### Tab `Thông minh`

- **Tự động khôi phục từ tiếng Anh / code**: Khi bật, `VietGoEngine` đối chiếu âm vị học tiếng Việt và `NSSpellChecker` để hoàn trả từ tiếng Anh, từ khóa lập trình, từ rút gọn `-n't` và URL/đường dẫn thay vì ép dấu tiếng Việt.
- **Chống lỗi lặp / nuốt chữ trên trình duyệt & Launcher**: Khi gõ vào ô có inline autocomplete hoặc thanh địa chỉ (Chrome, Safari, Arc, Dia, Brave, Edge, Firefox, Helium, Spotlight, Raycast, Alfred, Apple Mail, Excel), VietGo chèn ký tự đệm `U+0259` (`ə`) trước khi gửi `backspaceCount + 1` nhằm hủy vùng bôi xanh gợi ý mà không làm kẹt hay mất ký tự đầu, đồng thời tránh macOS Inline Predictive Text tự hoàn tất nhầm như trường hợp `dep` → `department`. Với các ô `<textarea>` đa dòng đã được Accessibility xác nhận (`AXTextArea`), cơ chế đệm này tự động được bỏ qua.

### Tab `Phím tắt`

- **Phím tắt chuyển Việt / Anh**: Mặc định `⌃ Space`. Có thể chọn nhanh `⌃ Space`, `⌥ Z`, `⌘ ⇧`, `⌃ ⇧`, `Fn`, hoặc nhấn nút **Đổi** để ghi nhận tổ hợp phím tùy chỉnh (hỗ trợ cả phím tắt chỉ gồm 2 modifier nhả tuần tự như `⌘⇧`).
- **Xử lý trùng phím tắt macOS**: Nếu `⌃ Space` trùng với phím chuyển Input Source mặc định của hệ thống, vào *System Settings → Keyboard → Keyboard Shortcuts… → Input Sources* và bỏ chọn mục chuyển Input Source, hoặc chuyển VietGo sang `⌥ Z` / `Fn`.

### Tab `Gõ thử`

- Cho phép kiểm tra nhanh mọi thiết lập Telex/VNI, dấu mới/cũ và auto-restore ngay trong cửa sổ ứng dụng.

---

## 4. Kiểm thử tự động & Công cụ kiểm chứng

### Bộ unit test (`VietGoEngineTests`)

```bash
swift test
```

Gồm 28 test method kiểm chứng các quy tắc Telex, VNI, dấu mới/cũ, auto-restore tiếng Anh, `yes`/`yess`/geminate, `w -> ư`, từ rút gọn, URL, Backspace đơn điệu trên đoạn văn dài và giới hạn hiệu năng `O(1)` cho chuỗi dài trên 48 ký tự. Để chạy kèm toàn bộ bộ kiểm thử trình duyệt thật cộng dồn (`R3_*` + `R4_*`), chạy:

```bash
bash scripts/qa/run_regression_qa.sh
```

### Công cụ kiểm chứng E2E qua `.cghidEventTap`

Script `scripts/validate_fast_chat_e2e.swift` hỗ trợ hai chế độ:

- Chạy kịch bản gõ tốc độ cao trực tiếp vào `NSTextView` và `WKWebView` để kiểm tra mất phím hoặc đảo phím khi gõ lướt (`1.300–2.000+ WPM`).
- Chạy ở chế độ worker (`--ime-worker`) nhận lệnh qua `stdin` phục vụ bộ kiểm thử trình duyệt thực tế:
  - `RESET`: Xóa trạng thái buffer của engine.
  - `BUNDLE <bundleID|->`: Giả lập bundle ID đích để kiểm tra nhánh trình duyệt/terminal/Office.
  - `METHOD <telex|vni>`: Chuyển đổi tức thời kiểu gõ giữa Telex và VNI trong phiên test.
  - `QUIT`: Dừng event tap và thoát sạch.

---

## 5. Xử lý sự cố thường gặp (Troubleshooting)

- **macOS báo *"Apple could not verify “VietGo” is free of malware..."* khi mở file `.dmg` tải về:**
  - Nguyên nhân: Bản phát hành mở dùng chữ ký ad-hoc (chưa qua notarization trả phí của Apple).
  - Cách xử lý: Bấm **Done** → **System Settings → Privacy & Security** → bấm **Open Anyway**, hoặc chạy `xattr -cr /Applications/VietGo.app`, hoặc cài đặt qua `brew install --cask haiquang/vietgo/vietgo`.
- **Đã build lại `dist/VietGo.app` nhưng gõ không ra dấu:**
  - Nguyên nhân thường gặp là bundle ad-hoc mới thay đổi chữ ký khiến macOS vô hiệu hóa quyền Accessibility cũ. Mở *System Settings → Privacy & Security → Accessibility*, xóa mục **VietGo** cũ và thêm lại bản mới (hoặc dùng chứng chỉ `VietGo Local CodeSign` ở Mục 2).
- **Ô nhập liệu là trường mật khẩu:**
  - Khi `IsSecureEventInputEnabled()` trả về `true`, VietGo tự động reset buffer và cho toàn bộ phím đi thẳng nhằm bảo đảm an toàn mật khẩu.
- **Đang bật bộ gõ khác của macOS (Nhật, Trung, Hàn, Apple Vietnamese):**
  - `EventTapManager` lắng nghe `kTISNotifySelectedKeyboardInputSourceChanged` và kiểm tra `TISCopyCurrentKeyboardInputSource()`. Khi phát hiện Input Source thuộc nhóm IME khác, VietGo tự nhường quyền để tránh xung đột.
- **Chuyển từ ứng dụng viết chữ sang ứng dụng thiết kế (Photoshop, Illustrator, Affinity, Figma):**
  - Nếu focus đang ở canvas ngoài ô nhập text, `VietGo` tự bypass để phím chữ dùng làm công cụ thiết kế (shortcut) không bị chặn hoặc xóa nhầm layer.
- **Sau khi máy ngủ (Sleep/Wake) hoặc chuyển người dùng (Fast User Switching):**
  - `EventTapManager` tự lắng nghe `didWakeNotification`, `screensDidWakeNotification`, `sessionDidBecomeActiveNotification` cùng watchdog 5 giây để tự bật lại `CGEventTap` nếu hệ thống tạm thời disable tap.

---

## 6. Tài liệu liên quan

- Tổng hợp toàn bộ các trường hợp đã xử lý và ánh xạ mã nguồn: [Thư mục `docs/handled-cases/`](handled-cases/README.md)
- Báo cáo kiểm toán đối chiếu 2.237 GitHub issues từ cộng đồng: [ISSUE_VALIDATION_AUDIT.md](ISSUE_VALIDATION_AUDIT.md)
- Ghi chú thiết kế giao diện: [DESIGN.md](../DESIGN.md)
