# 03 — Khôi phục từ tiếng Anh, mã nguồn, từ rút gọn và URL

Tài liệu này tổng hợp các quy tắc trong `SyllableComposer.swift`, `VietInputEngine.swift` và `VietnameseTables.swift` nhằm ngăn việc bỏ dấu nhầm lên từ tiếng Anh, từ khóa lập trình, từ rút gọn và đường dẫn mạng.

## 1. Sàng lọc âm vị học (`isPhonotacticallyValid`) & Coda

Mỗi keystroke khi bật `autoRestoreEnglish` đều qua kiểm tra cấu trúc âm tiết tiếng Việt (`Onset + Nucleus + Coda + Tone`):

| Quy tắc sàng lọc | Ví dụ đầu vào | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Tách `validOpenNuclei` và `validClosedNuclei` | `music`, `basic`, `coins`, `pains`, `trains`, `suits`, `vaixn`, `buaxn` | Giữ nguyên bản | Các nguyên âm đôi kết thúc bằng bán nguyên âm (`ai`, `oi`, `ui`, `ua`...) không được đi trước phụ âm cuối |
| Dừng sớm khi phụ âm cuối sai cấu trúc | `degree`, `depend`, `world`, `window`, `refresh`, `string`, `swift`, `function`, `class` | Giữ nguyên bản | Ngay khi nối ký tự vào `codaChars`, nếu `codaLower` không nằm trong `VietnameseTables.validCodas` thì bật `structuralFailure = true` |
| Luật chính tả phụ âm đầu `c/k/g/gh/ng/ngh/qu/kr` | `gets`, `ghost`, `nginx`, `queue`, `queues`, `nghaix`, `nghoo`, `gho`, `kar`, `giis` | Giữ nguyên bản | Kiểm tra tương hợp trực tiếp giữa `onsetLower` và nguyên âm đầu trong `isPhonotacticallyValid` |
| Phụ âm đầu ngoài tiếng Việt | `fix`, `file`, `zip`, `json`, `web`, `wifi`, `fww`, `jww`, `qww`, `qwerty` | Giữ nguyên bản | Không có mặt trong `VietnameseTables.validOnsets` |
| Ngoại lệ từ tiếng Anh dễ lọt quy tắc âm tiết trần | `term`, `more`, `post`, `data` | Giữ nguyên bản | Kiểm tra tập `VietnameseTables.englishNonWordExceptions` |

## 2. Chặn hồi sinh âm tiết đã hỏng (`Dead-Syllable Guard`)

Một âm tiết đã vi phạm thanh điệu với phụ âm cuối tắc (`c`, `ch`, `k`, `p`, `t` không nhận dấu huyền, hỏi, ngã) hoặc sai cấu trúc thì không được phép biến đổi lại ở các phím theo sau:

| Tình huống | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Từ số nhiều có âm cuối tắc | `texts`, `sorts`, `ports`, `parts`, `carts`, `darts`, `softs`, `lofts`, `rafts`, `lifts`, `gifts` | Giữ nguyên bản | `applyTone` từ chối biến đổi khi âm tiết hiện tại với thanh điệu trước đó đã trượt `isPhonotacticallyValid` |
| Tên framework & biến code có dấu kết | `nextjs`, `nuxtjs`, `quartz`, `hertz`, `wartz` | Giữ nguyên bản | Giữ nguyên lỗi âm vị của `j`/`z` để trả về toàn bộ `rawKeys` |
| Đúp nguyên âm cuối trên âm tiết đã hỏng coda + thanh | `decree` | `decree` (tránh biến thành `dẻce`) | `applyShape` kiểm tra lại `isPhonotacticallyValid` trước khi đổi hình dáng hoặc kích hoạt `explicitEscape` (chỉ chừa trường hợp `ua` chờ `uâ` khi có coda) |

## 3. Cụm `wr-`, vần trung gian và `d...d` khoảng cách xa

| Tình huống | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Cụm `wr-` theo sau bởi nguyên âm | `wrong`, `wrongs`, `write`, `wrap` | `wrong`, `wrongs`, `write`, `wrap` | Không ghép `w` đứng đầu thành `ư` khi theo sau là `r` + nguyên âm; `wr ` → `ử `, `wf ` → `ừ `, `uowngr ` → `ưởng ` vẫn hoạt động |
| Hoàn trả vần trung gian khi kết thúc từ | `lieus `, `milieus `, `cuois `, `ruous `, `tuois `, `tuyetj `, `ddien ` | Giữ nguyên bản kèm dấu cách | `VietInputEngine.processKey` gọi `compose(..., isFinalizingWord: true)` đối chiếu `intermediateOnlyNuclei` (`ie`, `ye`, `uo`, `ưo`, `uye`, `ieu`, `yeu`, `uoi`, `uou`, `uay`) |
| Hoàn trả `ă`/`â` mở khi chốt từ | `ddaxa `, `law `, `saw `, `raw `, `asa `, `AWS `, `NASA ` | Giữ nguyên bản | Khi `isFinalizingWord == true`, âm tiết có phụ âm đầu đi với `ă`/`â` mà không có phụ âm cuối bị loại khỏi tiếng Việt |
| Chặn `d...d` khoảng cách xa trên từ tiếng Anh 5+ ký tự | `defend`, `defends`, `depend` | `defend`, `defends`, `depend` | Ghi nhận `hadLongDistanceDStroke = (!vowels.isEmpty)` khi biến `d → đ`; nếu `rawKeys.count >= 5` và `isValidEnglishWord` đúng thì trả nguyên bản (vẫn giữ `duowngd` → `đương`, `ddeenf` → `đền`, `ddeens` → `đến`) |

## 4. Từ rút gọn `-n't`, URL, đường dẫn và chữ số VNI

| Tình huống | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Từ rút gọn tiếng Anh dạng `-n't` | `doesn't work`, `isn't it`, `won't fail`, `hasn't changed`, `didn't` | `doesn't work`, `isn't it`, `won't fail`, `hasn't changed`, `didn't` | Khi nhận phím `t`/`T` ngay sau dấu `'`/`’` và từ vừa chốt trước đó trong `committedHistory` kết thúc bằng `n`/`N` nhưng đã bị đổi dấu (`doén`, `ín`, `ươn`, `hán`, `đin`), engine khôi phục `prev.rawKeys + sep + char` |
| Toàn bộ phân đoạn URL sau `*://` | `https://docs.google.com/forms tieeps `, `http://localhost:3000/test moiw ` | `https://docs.google.com/forms tiếp `, `http://localhost:3000/test mơi ` | Dò chuỗi `://` qua `prev2StreamChar`/`prev1StreamChar`, giữ `urlLiteralDepth > 0` suốt mọi token con cho tới khi gặp ký tự kết thúc `isURLTerminator` (khoảng trắng, ngoặc/nháy, dấu phẩy, chấm phẩy) |
| Toàn bộ phân đoạn đường dẫn home sau `~/` đầu từ | `~/Works/test/forms dduowcj `, `cd ~/Works/was/test lafm `, `~/was `, `a.wav` | `~/Works/test/forms được `, `cd ~/Works/was/test làm `, `~/was `, `a.wav` | Dò `~/` khi ký tự trước `~` là `nil` hoặc `isURLTerminator`; ngoài ra chặn `w` đứng đầu sau `/`, `\`, `~`, `.`, `@`, `:`, `_`, `-` qua `isPathOrSymbolPrefix` |
| Bảo toàn từ ghép gạch chéo tiếng Việt | `anh/chij ` | `anh/chị ` | Ký tự trước `/` là `h` (không phải `:` hoặc `~` đầu từ) nên không kích hoạt `urlLiteralDepth` |
| Bảo toàn chữ số trong chế độ VNI | `100%`, `Chrome2`, `v2.0` | `100%`, `Chrome2`, `v2.0` | `100%` bắt đầu bằng chữ số khi chưa có từ đang gõ (`hasActiveWord == false`); `Chrome2` giữ nguyên `rawKeys` vì `Chrome` đã kích hoạt `structuralFailure` trước khi gặp số `2` |
