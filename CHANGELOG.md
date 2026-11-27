# Lịch sử phiên bản (Changelog)

Mọi thay đổi đáng chú ý của **VietGo** được ghi lại tại đây.

## [1.0.1] - 2026-11-27

### Đã sửa
- Sửa lỗi hit-testing trên giao diện SwiftUI: trước đó các nút dùng `.buttonStyle(.plain)` chỉ nhận click trực tiếp vào ký tự chữ/icon thay vì toàn khung nền (`Color.clear` / `Spacer()`). Đã bổ sung `.contentShape(...)` phủ trọn khung bấm cho thanh chuyển 4 tab (`Bộ gõ`, `Thông minh`, `Phím tắt`, `Gõ thử`), thẻ chọn `Telex`/`VNI`, badge trạng thái quyền, nút `Đổi phím tắt…`, các nút `Mẫu nhanh`, chip mẫu ở tab `Gõ thử`, và 5 hàng cài đặt có nút gạt.
- Chuyển khoảng trống giữa phần nhãn và nút gạt trong `VGSettingRow` vào padding nội bộ (`spacing: 0`) để không còn khe chết trước switch.

### Đã thêm
- Cho phép bấm trực tiếp vào badge icon `V`/`E` trên thanh trạng thái để bật/tắt nhanh chế độ Tiếng Việt/Tiếng Anh.
- Hỗ trợ tham số khởi chạy `--open-settings` để mở thẳng cửa sổ cài đặt khi khởi động.

## [1.0.0] - 2026-11-27

### Đã thêm
- Phát hành phiên bản đầu tiên **VietGo v1.0.0** cho macOS 14.0+ (tối ưu Apple Silicon).
- Lõi xử lý âm tiết `VietGoEngine` thuần Swift hỗ trợ đầy đủ **Telex** và **VNI**, xuất trực tiếp Unicode dựng sẵn (NFC) không gạch chân.
- Hỗ trợ bỏ dấu tự do, chuyển đổi hai chiều `uô ↔ ươ`, vần `oă`, `ưu`, `oo` kèm phụ âm cuối (`voọc`, `soóc`, `xoong`), địa danh `Đắk Lắk` / `Krông Búk`, từ viết tắt chứa `Đ` (`SĐT`, `QĐ`, `NĐ`), tùy chọn dấu mới (`hòa, khỏe, thủy`) hoặc dấu cũ (`` `hoà, khoẻ, thuỷ` ``), gõ `w` đơn thành `ư` và gõ tắt `[`/`]`.
- Cơ chế tự động khôi phục từ tiếng Anh, từ khóa code, định danh `camelCase` / `snake_case`, từ viết tắt lặp phím (`URRL` → `URL`), cụm `wr-`, âm tiết hỏng (`texts`, `sorts`, `degree`, `decree`), `d...d` khoảng cách xa (`defend`, `defends`), từ rút gọn `-n't` (`doesn't`, `won't`, `isn't`), cùng toàn bộ các phân đoạn URL (`*://...`) và đường dẫn `~/...`.
- Đồng bộ Backspace tối thiểu bằng LCP, khôi phục từ sau Space/dấu câu (`committedHistory`), dịch dấu khi xóa coda (`hoafn<BS>` → `hòa`) và giữ bất biến co ngắn đơn điệu trên vần trung gian.
- Giao diện Menu Bar (`V`/`E`) cùng cửa sổ cài đặt SwiftUI 4 tab (`Bộ gõ`, `Thông minh`, `Phím tắt`, `Gõ thử`) hiển thị phiên bản hiện tại trong menu.
- Script đóng gói release (`scripts/package_release.sh`) tạo `.dmg`, `.zip` và `SHA256SUMS.txt` cùng GitHub Actions workflow phát hành tự động theo tag `v*`.

### Đã tối ưu & Tương thích
- Bắt phím ở `.cghidEventTap` kết hợp `tapPostEvent(proxy)`, `CGEventSource(.privateState)` và `injectionSemaphore` để giữ đúng thứ tự phím khi gõ nhanh tốc độ 140–250+ WPM.
- Sử dụng ký tự đệm `U+0259` (`ə`) xử lý inline autocomplete trên trình duyệt và Launcher mà không kích hoạt chấp nhận nhầm macOS Inline Predictive Text (`dep` → `department`) hay bị WebKit nuốt ký tự.
- Truy vấn Accessibility trên background queue (`axQueryQueue`), tự bỏ qua ký tự đệm khi xác nhận `AXTextArea`, tự ngắt trên canvas app thiết kế và ô mật khẩu (`Secure Input`), điều nhịp chuyên biệt cho Terminal/IDE/Microsoft Office và tự phục hồi event tap sau Sleep/Wake.
