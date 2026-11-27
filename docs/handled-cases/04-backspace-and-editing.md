# 04 — Backspace, đồng bộ con trỏ và giới hạn hiệu năng

Tài liệu này mô tả cách `VietInputEngine.swift` đồng bộ trạng thái buffer với vùng văn bản trên màn hình khi xóa ký tự, sửa từ cũ hoặc dùng phím điều hướng.

## 1. Tối thiểu số lần Backspace (LCP) & Xóa lùi thông minh

| Tình huống | Chuỗi thao tác | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Chỉ xóa phần hậu tố thay đổi (Longest Common Prefix) | Đang có `tiêng`, gõ `s` | Chỉ gửi 3 Backspace + `ếng` → `tiếng` | `makeReplaceAction` tìm chỉ số `lcp` chung giữa `oldDisplayed` và `newDisplayed` |
| Xóa lùi sửa ký tự cuối | `tieengs<BS><BS>p` | `tiếp` | `handleBackspace()` tái tạo `newRawKeys` từ chuỗi còn lại qua `canonicalRawKeys` |
| Phục hồi từ đã chốt sau Space hoặc dấu câu | `co <BS>s`, `tieeng <BS>s`, `nhu <BS>w`, `bong,<BS>s`, `hoa <BS>f`, `go go<BS><BS><BS>x` | `có`, `tiếng`, `như`, `bóng`, `hòa`, `gõ` | `committedHistory` (tối đa 64 phần tử `CommittedWord`) nạp lại từ và dấu phân cách cũ khi `displayed` trống |
| Hoàn thiện từ gõ thiếu dấu sau Space + Backspace | `ddieu <BS>ef`, `ddieuf <BS>e` | `điều` | `VietInputEngine` chỉ gắn `isLiteralToken = true` khi `midWordResult.didAutoRestore`, giữ `committedLiteral = false` cho vần trung gian chốt dở để quay lại gõ tiếp dấu mũ/thanh |
| Tự đặt lại vị trí dấu thanh khi xóa phụ âm cuối | `hoafn<BS>`, `khoern<BS>` | `hòa`, `khỏe` | `SyllableComposer.compose(rawKeys: newRawKeys)` tính lại `toneTargetIndex` khi mất coda |
| Phục hồi âm tiết khi xóa phím dấu dư | `nhaafmf<BS>` | `nhầm` | Tái tổ hợp `canonicalRawKeys` của `nhaafm` cho ra đúng từ hợp lệ |
| Bất biến co ngắn đơn điệu trên vần trung gian | `tiengs` (`tiéng`) → `<BS>` → `<BS>` → `<BS>` → `<BS>` → `<BS>` | Co ngắn đều từng bước `tién` → `tié` → `ti` → `t` → rỗng (không bung thành `ties`) | `if recomposed.count > afterBS.count` giữ nguyên `afterBS` và trả `.passThrough` thay vì thay thế bằng `rawKeys` thô |
| Nhấn giữ phím Backspace (`autorepeat`) | `hoanf` + giữ Backspace lặp lại (`keyCode == 51`) | Xóa khớp buffer, không bỏ qua lặp phím | `EventTapManager` chỉ cho `isAutorepeat` đi thẳng với phím khác `51`; phím `51` luôn qua `engine.handleBackspace()` |

## 2. Điều hướng con trỏ, chọn vùng và thao tác chỉnh sửa

| Phím / Tổ hợp điều khiển | Ngữ cảnh áp dụng | Hành vi hệ thống | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| `Left Arrow`, `Right Arrow` | Chèn từ giữa câu trong Omnibox hoặc `contenteditable` | `tôi mới đi học vui vẻ `, `bạn thử kiểm tra lại xem` | `navigationKeyCodes` (`115..126`, `36`, `76`, `48`, `53`, `117`) gọi `engine.reset(clearHistory: true)` |
| `Cmd + A` ghi đè giữa từ | `nhieeuf nguowif ddang` + `Cmd+A` + `mowis lamf laij tuwf ddaauf oorn ddinhj` | `mới làm lại từ đầu ổn định` | Mọi tổ hợp có `.maskCommand`, `.maskControl`, `.maskAlternate` đều xóa buffer ngay để không dính từ cũ |
| `Option + Backspace` xóa cả từ | `xin chafo nhaafmf` + `Opt+BS` + `banj mowis ddeens` | `xin chào bạn mới đến` | Reset engine ngay khi gặp `.maskAlternate` trước khi phím xóa thực thi |
| `Shift + Left Arrow` chọn lùi & thay thế | `ddasnh gias cuar banj` + `Shift+Left × 3` + `nguowif dungf` | `đánh giá của người dùng` | Reset buffer khi di chuyển selection sang trái |
| `Tab` chuyển ô input giữa từ | Ô 1 gõ `hoaf` + `Tab` + ô 2 gõ `binhf ` | Ô 1 giữ `hòa`, ô 2 thành `bình ` | Keycode `48` trong `navigationKeyCodes` chốt ô 1 và làm sạch engine trước khi sang ô 2 |
| `Escape` đóng popup gợi ý giữa từ | `tag @dev` + `Esc` + ` nguowif_dungf ddaau ` | `tag @dev người_dùng đâu ` | Keycode `53` đóng popup và reset từ đang dở |
| Nhấn giữ lặp phím chữ (`autorepeat != 0`) | `chafo` + giữ `a` + ` banj mowis ` | `chàoaa bạn mới ` | Khi `keyCode != 51` và có cờ autorepeat, engine reset buffer và cho ký tự đi thẳng |
| Phím chức năng macOS (`F1`–`F20`), Escape, Delete | Unicode scalar điều khiển `< 0x20` (trừ `\t`, `\n`, `\r`), `0x7F`, `0xF700...0xF8FF` | Trả `.passThrough` và xóa buffer | Khớp cả ở tầng `EventTapManager` lẫn `VietInputEngine.processKey` |
| Bảo vệ hiệu năng chuỗi dài | Chuỗi không dấu/lỗi dài > 48 ký tự (`rawIdx >= 48`) | Hoàn tất trong < `20 ms`, không phình `O(n²)` | `SyllableComposer` dừng xử lý sớm và hoàn trả nguyên `rawKeys` |
