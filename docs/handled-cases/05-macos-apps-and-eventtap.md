# 05 — Tương thích ứng dụng macOS & Tầng `CGEventTap`

Tài liệu này tổng hợp các tình huống đặc thù ở mức hệ điều hành và ứng dụng đích được xử lý trong `EventTapManager.swift` và `AppSettings.swift`.

## 1. Bắt và bơm sự kiện phím tốc độ cao

| Vấn đề | Giải pháp trong VietGo | Phạm vi áp dụng |
| :--- | :--- | :--- |
| Trễ nhịp hoặc đảo phím khi gõ nhanh (`140–250+ WPM`) | Bắt phím ở `.cghidEventTap`, đồng bộ bằng `injectionSemaphore`, bơm sự kiện qua `event.tapPostEvent(proxy)` từ nguồn `.privateState` và giữ lại system flag `NX_NONCOALESCEDMASK` (`0x20000000`) | Toàn hệ thống |
| Dính phím modifier (`Shift`, `Command`, `Option`, `Control`, `CapsLock`, `Fn`) vào ký tự thay thế | Loại bỏ `strippedModifierFlags` trên các event Backspace và Unicode tổng hợp trong `postSyntheticEvent` | Toàn hệ thống |
| Mất chữ `á`/`à` hoặc sai encoding do chuỗi tổ hợp NFD | Toàn bộ chuỗi đầu ra được chuẩn hóa NFC qua `.precomposedStringWithCanonicalMapping` trước khi bơm (trừ ngoại lệ `ý`/`Ý` trên Microsoft Office) | Toàn hệ thống |

## 2. Xung đột trình duyệt, Inline Autocomplete & Inline Predictive Text

| Tình huống | Cơ chế xử lý | Ghi chú kỹ thuật |
| :--- | :--- | :--- |
| Thanh địa chỉ / omnibox trình duyệt & Launcher bôi xanh gợi ý (`đà[ nẵng]`) | Bật `applyAutocompleteFix` với nhóm `browserBundleIDs` và `alwaysAutocompleteBundleIDs`: gửi 1 ký tự đệm rồi gửi `backspaceCount + 1` | Áp dụng cho Chrome, Safari, Arc, Dia, Brave, Edge, Firefox, Opera, Opera Air, Vivaldi, Orion, Zen, Comet, ChatGPT Atlas, Helium, Cốc Cốc, Spotlight, Raycast, Alfred, Mail, Excel |
| Tránh chớp ký tự thừa, chặn Inline Predictive Text (`dep[artment]`) & tránh WebKit nuốt ký tự rỗng | Dùng **`U+3164`** (`ㅤ`, Hangul Filler, `Lo`, độ rộng `0,00 px`, 1 UTF-16 code unit, không phải `Zs` hay `Cf`) và bỏ qua chèn ký tự đệm khi nhấn `Backspace` | Giữ đúng `depend` → `depend`, `depj` → `dẹp`, xóa chỉ với 1 Backspace và hủy selection ở `#omnibox-input` (`ddafs` → `đá`, `R6_01`) mà không nháy chữ |
| Ô nhập đa dòng `<textarea>` trên web & chuyển focus qua `Tab` | Truy vấn AX bất đồng bộ trên `axQueryQueue` (`timeout 35 ms`, làm mới 2 nhịp `0,05 s` + `0,18 s` khi click chuột, đổi app, `Cmd+L/T/K/F`, `Tab`); đặt `cachedIsExplicitWebTextArea = true` với `AXTextArea` | Nhận diện kịp `AXTextArea` khi chuyển focus bằng `Tab` và giữ nhịp thay thế `< 2,5 ms` (sub-frame ở `120 Hz`) trên trình duyệt/ứng dụng thường |
| Bảo toàn DOM có thẻ định dạng & React controlled input | Gõ vào cuối đoạn chứa `<b>`, `<code>` trong `contenteditable` giữ nguyên cấu trúc thẻ; `selectionStart`/`selectionEnd` trong React controlled input đồng bộ chuẩn NFC ở tốc độ cao | Kiểm chứng qua Browser QA `R3_06` và `R3_09` |

## 3. Ứng dụng chuyên biệt: Terminal, Microsoft Office và Design Tools

| Nhóm ứng dụng | Cách nhận diện | Hành vi điều chỉnh |
| :--- | :--- | :--- |
| **Terminal, PTY & IDE** | `terminalAndPTYBundleIDs` (Terminal, iTerm2, Warp, Ghostty, kitty, Alacritty, WezTerm, VSCode, Cursor, Zed, Antigravity, Zalo) và prefix `com.jetbrains.*` | Tăng nhịp delay (`2.000 µs` mỗi Backspace, `4.000 µs` sau Backspace, `2.000 µs` mỗi chunk, `3.000 µs` settle) để tránh rớt phím trên PTY / Claude Code CLI |
| **Microsoft Office (`ý`/`Ý`)** | `microsoftOfficeBundleIDs` (Word, PowerPoint, Outlook) và `Excel` trong `alwaysAutocompleteBundleIDs` | Tăng nhịp pacing (`2.000–5.000 µs`); riêng Word/PowerPoint/Outlook phân tách `ý`/`Ý` sang dạng NFD (`requiresDecomposedAcuteY`) và cộng bù thêm Backspace khi xóa ký tự này |
| **Ứng dụng thiết kế (`canvas`)** | `designCanvasBundleIDs` (Photoshop, Illustrator, Affinity Designer 2, Affinity Photo 2, Figma) | Kiểm tra `role` AX; khi focus không nằm trên `AXTextField`, `AXTextArea`, `AXComboBox`, `AXSearchField`, `AXWebArea`, bật `cachedIsCanvasNonTextInDesignApp = true` để nhường phím tắt vẽ |

## 4. An toàn, xung đột bộ gõ hệ thống & tự phục hồi

- **Ô mật khẩu (`Secure Input`)**: Kiểm tra `IsSecureEventInputEnabled()` trước mọi lần xử lý; tự reset buffer và trả phím nguyên vẹn.
- **Xung đột Input Source**: Lắng nghe `kTISNotifySelectedKeyboardInputSourceChanged`, kiểm tra `TISCopyCurrentKeyboardInputSource()` để tự bypass nếu người dùng chuyển sang bộ gõ Nhật (`Japanese`, `Kotoeri`), Trung (`SCIM`, `TCIM`), Hàn (`Korean`) hoặc Apple Vietnamese (`Vietnamese`, `com.apple.inputmethod`).
- **Phím tắt modifier nhả tuần tự**: `handleModifierOnlyShortcutFlags` theo dõi trạng thái nhấn và nhả tuần tự không kèm phím khác trong ngưỡng `0,025 s – 1,5 s`, hỗ trợ `⌘⇧`, `⌃⇧` và `Fn`.
- **Tự phục hồi Event Tap**: Lắng nghe `didWakeNotification`, `screensDidWakeNotification`, `sessionDidBecomeActiveNotification`, `sessionDidResignActiveNotification`, sự kiện `tapDisabledByTimeout`/`tapDisabledByUserInput` và timer watchdog chu kỳ `5 giây` để tự khởi tạo lại tap khi hệ thống mở khóa hoặc cấp quyền.
