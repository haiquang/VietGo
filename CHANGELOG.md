# Lịch sử phiên bản (Changelog)

Tóm tắt các tính năng mới và cải tiến qua từng phiên bản **VietGo** dành cho người dùng macOS.

## [1.0.2] - 2026-11-27

### Cải tiến & Sửa lỗi
- **Xóa từng chữ và từng từ mượt mà, không bị nhảy chữ:** Khắc phục lỗi khi xóa ngược trên đoạn văn dài có xen kẽ tiếng Anh và tiếng Việt khiến một số từ bị sập thành dấu tiếng Việt hoặc nuốt nhiều ký tự cùng lúc. Kể cả khi nhấn từng nhịp hay nhấn giữ phím `Delete` / `Backspace` để xóa nhanh, con trỏ luôn lùi đều từng ký tự một.
- **Giữ nguyên các từ tiếng Anh thông dụng khi gõ chung với tiếng Việt:**
  - Giữ đúng chữ khi gõ kéo dài âm cuối như `yess`, `yesss` thay vì tự cắt mất chữ `s` thành `yes`.
  - Nhận diện tự nhiên các từ kết thúc bằng hai phụ âm giống nhau như `less`, `mess`, `boss`, `loss`, `pass`, `miss`, `kiss`, `mass`, `guess`, `chess`, `swiss`, `tariff`, `buff`, `purr`.
  - Không còn biến đổi nhầm các từ như `away`, `awake`, `aware`, `award`, `virus`, `terms`, `turns`, `burns`, `horns`, `surf`, `turf`, `dwarf`.
- **Gõ chuẩn cả chữ `w` tiếng Anh lẫn gõ tắt `w` thành `ư` tiếng Việt:** Giữ nguyên các từ tiếng Anh bắt đầu bằng `w` (`was`, `war`, `wax`, `won`, `woo`, `wow`, `worm`, `worn`), đồng thời vẫn hỗ trợ trọn vẹn cách gõ nhanh `w` thành `ư` trong tiếng Việt (`như`, `nhưng`, `thử`, `chữ`, `chưa`, `được`, `trường`, `người`, `giữ`, `giữa`, `rượu`...).

## [1.0.1] - 2026-11-27

### Cải tiến & Sửa lỗi
- **Bấm chọn thoải mái toàn khung trong Cài đặt:** Khắc phục lỗi trước đây phải bấm trúng vào chữ hoặc nút gạt nhỏ mới chuyển được. Giờ đây bạn có thể bấm vào bất kỳ chỗ nào trên các thẻ tab (`Bộ gõ`, `Thông minh`, `Phím tắt`, `Gõ thử`), thẻ chọn `Telex` / `VNI`, cả dòng của các tùy chọn bật/tắt, nút đổi phím tắt, các nút mẫu nhanh và huy hiệu trạng thái quyền.
- **Chuyển nhanh Việt / Anh từ góc trên cửa sổ:** Bạn có thể bấm trực tiếp vào biểu tượng chữ **V** / **E** ở góc trên bên trái cửa sổ Cài đặt để bật hoặc tắt chế độ gõ tiếng Việt.

## [1.0.0] - 2026-11-27

### Tính năng mới
- **Phát hành VietGo v1.0.0 cho macOS 14 trở lên (Apple Silicon):** Bộ gõ tiếng Việt gọn nhẹ trên thanh menu (`V` / `E`), bỏ dấu trực tiếp mượt mà và không bị gạch chân khó chịu khi gõ trên trình duyệt, phần mềm chat hay trình soạn thảo văn bản.
- **Hỗ trợ đầy đủ Telex & VNI, gõ dấu tự do:** Hỗ trợ bỏ dấu ở bất kỳ vị trí nào trong từ, giữ đúng quy tắc dấu mới (`hòa, khỏe, thủy`) hoặc dấu cũ (`` `hoà, khoẻ, thuỷ` ``), xử lý mượt các vần đặc trưng (`ươ`, `oă`, `ưu`, `oo`, `giữ`, `giữa`, `Đắk Lắk`, `Krông Búk`) và các từ viết tắt in hoa (`SĐT`, `QĐ`, `NĐ`).
- **Tự nhận diện tiếng Anh, từ viết tắt và đường dẫn:** Tự giữ nguyên bản các từ tiếng Anh, từ rút gọn (`doesn't`, `won't`, `isn't`, `hasn't`), từ viết tắt (`URL`, `JSON`, `CORS`), địa chỉ web (`https://...`) và đường dẫn thư mục (`~/...`) khi gõ xen kẽ với tiếng Việt.
- **Tùy biến linh hoạt & an toàn:** Cho phép tùy chỉnh phím tắt chuyển Việt/Anh (gồm cả `Fn` hoặc tổ hợp hai phím modifier), giữ tab **Gõ thử** ngay trong app, tự động tạm ngưng khi bạn nhập mật khẩu hoặc khi chuyển sang bộ gõ Nhật/Trung/Hàn.

### Cải tiến & Độ ổn định
- **Gõ nhanh tốc độ cao không rớt phím:** Giữ đúng thứ tự chữ khi gõ lướt nhanh và tránh hiện tượng nhảy chữ hoặc dính gợi ý trên Chrome, Safari, Arc, Spotlight, Raycast, Terminal và Microsoft Office.
- **Xóa và sửa dấu tự nhiên bằng Backspace:** Có thể nhấn Backspace quay lại sửa dấu cho từ vừa gõ xong sau dấu cách hoặc dấu câu, tự động căn lại vị trí dấu khi xóa bớt chữ cuối mà không bị bung chữ lạ.
