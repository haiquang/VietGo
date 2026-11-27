# 01 — Ghép âm tiết Telex, VNI và các vần đặc biệt

Tài liệu này tổng hợp toàn bộ quy tắc biến đổi âm tiết tiếng Việt trong `SyllableComposer.swift` và `VietnameseTables.swift`.

## 1. Telex cốt lõi & Bỏ dấu tự do

Hệ thống tái phân tích toàn bộ chuỗi `rawKeys` từ đầu âm tiết nên hỗ trợ bỏ dấu ở bất kỳ vị trí nào trước hoặc sau khi hoàn tất phụ âm cuối:

| Tình huống | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Telex cơ bản có dấu | `xin chaof`, `tieengs vieetj`, `nguwowif`, `dduwowcj` | `xin chào`, `tiếng việt`, `người`, `được` | `SyllableComposer.composeResult` |
| Đảo thứ tự phím dấu và móc/mũ | `truongwf`, `truwongf`, `duocdwj`, `vietej`, `hanfh`, `cuar`, `cura`, `taij`, `taji`, `mowis` | `trường`, `trường`, `được`, `việt`, `hành`, `của`, `của`, `tại`, `tại`, `mới` | Áp thanh điệu `tone` và hình dáng nguyên âm độc lập rồi đặt dấu tại `toneTargetIndex` |
| Đảo chữ `d` tạo `đ` muộn (từ không phải tiếng Anh) | `dangd`, `duowngd` | `đang`, `đương` | `strokeInitialD` tìm âm đầu `d`/`D` khi chưa `hasStrokeD` |
| Chuyển dấu thanh ngay trên từ | `as` → `asf`, `tiengs` → `tieengs` | `á` → `à`, `tiéng` → `tiếng` | `applyTone` ghi đè `tone` mới |
| Xóa dấu thanh bằng `z` / `0` | `asfz`, `tieengsz`, `a10` (VNI) | `a`, `tiêng`, `a` | `tone = .none` khi gặp `z` (Telex) hoặc `0` (VNI) |
| Chữ `w` đơn thành `ư` (`standaloneW`) | `nhw`, `wf`, `wr` | `như`, `ừ`, `ử` | Nhánh `standaloneW` tạo `VowelSlot("u", .horn)` |

## 2. Chế độ VNI & Quy tắc đặt dấu

| Tình huống | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Gõ VNI chuẩn & bỏ dấu tự do | `xin cha2o vie65t nam`, `tru7o72ng`, `truong72`, `d9u7o75c`, `nguo72i` | `xin chào việt nam`, `trường`, `trường`, `được`, `người` | Nhánh `.vni` (`6` mũ, `7` móc, `8` trăng, `9` `đ`, `1..5` thanh, `0` xóa dấu) |
| Quy tắc dấu mới (mặc định `ToneStyle.modern`) | `hoaf`, `khoer`, `thuyr`, `tuyf`, `toans` | `` `hòa`, `khỏe`, `thủy`, `tùy`, `toán` `` | `toneTargetIndex` ưu tiên âm chính sau với âm tiết mở `oa`, `oe`, `uy` |
| Quy tắc dấu cũ (`ToneStyle.traditional`) | `hoaf`, `khoer`, `thuyr`, `tuyf`, `toans` | `` `hoà`, `khoẻ`, `thuỷ`, `tuỳ`, `toán` `` | `toneTargetIndex` đặt dấu lên âm thứ nhất nếu không có dấu mũ/móc và không có coda |

## 3. Tổ hợp nguyên âm & âm đầu đặc thù (`gi`, `qu`, `ươ ↔ uô`, `oă`, `ưu`, `oo`)

| Nhóm vần | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Cụm `gi` + nguyên âm & `gi` đơn | `gieengs`, `gieets`, `giuwx`, `giuwax`, `giuwowngf`, `gif`, `ginf`, `gir` | `giếng`, `giết`, `giữ`, `giữa`, `giường`, `gì`, `gìn`, `gỉ` | `promoteQuOrGiIfNeeded()` ghép `i` vào `onsetChars` khi có nguyên âm theo sau |
| Cụm `gi` + `w` thành `giư` | `giw`, `giwx`, `giwa`, `giwax` | `giư`, `giữ`, `giưa`, `giữa` | Nhánh đặc biệt promote `g` + `i` + `w` → onset `gi` + `ư` |
| Cụm `qu` & vần môi `huơ` / `khuơ` / `thuở` | `quas`, `quoocs`, `quys`, `quynhf`, `quow`, `huow`, `khuow`, `khuowr`, `thuowr`, `khuya`, `khuyur` | `quá`, `quốc`, `quý`, `quỳnh`, `quơ`, `huơ`, `khuơ`, `khuở`, `thuở`, `khuya`, `khuỷu` | Giữ `u` trong `onsetChars` cho `qu`; giữ `uơ` không móc `u` với âm đầu `h`/`th`/`kh` khi âm tiết mở |
| Chuyển đổi tự động `uơ → ươ` và `uô ↔ ươ` | `truwow`, `truwo`, `nguwowi`, `truoonw`, `truwongo`, `cuowoi`, `truowo` | `trươ`, `trươ`, `ngươi`, `trươn`, `truông`, `cuôi`, `truô` | `applyShape(.horn)` và bước kiểm tra `vowels` khi thêm nguyên âm thứ 3 hoặc coda |
| Vần `oă` ưu tiên dấu trăng cho `a` | `thoangws`, `thoawngs`, `thoawsng`, `hoawcj`, `xoawn` | `thoắng`, `thoắng`, `thoắng`, `hoặc`, `xoăn` | Phát hiện cặp `o` + `a` trong `vowels` trước `w` để áp `.breve` cho `a` thay vì `.horn` cho `o` |
| Vần `ưu` ưu tiên móc cho `u` thứ nhất | `uuw`, `cuuws`, `cuuwf`, `luuw`, `huuw`, `cuu71` (VNI) | `ưu`, `cứu`, `cừu`, `lưu`, `hưu`, `cứu` | Tìm cặp `u` + `u` liền kề để gắn `.horn` vào phần tử đầu tiên |
| Nguyên âm đôi `oo` kèm coda `c` / `ng` | `xooong`, `vooocj`, `sooocs`, `Thooongf`, `looongf` | `xoong`, `voọc`, `soóc`, `Thoòng`, `loòng` | Chèn `VowelSlot("o")` thứ 2 tại `ooEscapeRawIndex` và cho phép coda `c`/`ng` |
| Vần ba `oao`, `oeo` & từ hiếm `gỵa` | `khoeof`, `ngoaos`, `gyaj` | `khoèo`, `ngoáo`, `gỵa` | Chặn biến `o` thành `ô` trong `oao`/`oeo`; không đẩy `y` vào onset với `g` |

## 4. Chữ hoa, viết tắt, địa danh và ký tự dựng sẵn

| Tình huống | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Bảo toàn chữ hoa đầu từ & toàn từ | `Vieetj`, `VIEETJ`, `Ddaf Nawngx`, `DDAF NAWNGX` | `Việt`, `VIỆT`, `Đà Nẵng`, `ĐÀ NẴNG` | Lưu cờ `isUppercase` trên từng `onsetChars` và `VowelSlot` |
| Từ viết tắt in hoa chứa `Đ` | `SDDT`, `QDD`, `NDD`, `DdL`, `DdN` | `SĐT`, `QĐ`, `NĐ`, `ĐL`, `ĐN` | Ngoại lệ trong `isPhonotacticallyValid` cho cụm phụ âm toàn chữ hoa chứa `Đ` |
| Địa danh có âm cuối `k` hoặc âm đầu `kr` | `Ddawsk Lawsk`, `Ddawks Lawks`, `Kroong Buks` | `Đắk Lắk`, `Đắk Lắk`, `Krông Búk` | Cho phép `k` trong `validCodas` (khi đi với `ă`/`u`) và `kr` trong `validOnsets` (khi đi với `o`) |
| Gõ tiếp trên ký tự Unicode dựng sẵn | `TƯ2` (VNI), `mèoj` | `TỪ`, `mẹo` | `VietnameseTables.decodeVowel` giải mã trực tiếp nguyên âm có dấu sẵn |
| Gõ tắt dấu ngoặc (`bracketShortcuts: true`) | `h[`, `h]` | `hơ`, `hư` | Ánh xạ `[` → `ơ`, `]` → `ư` khi bật cấu hình |
| Gõ `â` / `ă` đơn đứng riêng hoặc trong backtick | `` `aa` ``, `` `aw` ``, `` `AA` ``, `` `AW` ``, `` `aas` ``, `aa `, `aw ` | `` `â` ``, `` `ă` ``, `` `Â` ``, `` `Ă` ``, `` `ấ` ``, `â `, `ă ` | Cho phép `â`/`ă` khi không có phụ âm đầu (`onsetChars.isEmpty`) |
| Chặn dấu mũ vô lý như `ưâ` | `chuwaa` (khi tắt auto-restore), `tuaanf` | `chưaa`, `tuần` | `applyShape(.circumflex)` cho `a` chỉ hợp lệ sau `u` không dấu móc |
