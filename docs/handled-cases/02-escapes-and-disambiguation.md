# 02 — Thoát dấu phím đúp và phân giải từ vựng

Tài liệu này mô tả cơ chế double-key escape, nối tiếp ký tự sau khi escape và phân biệt từ phụ âm đơn/kép tiếng Anh trong `SyllableComposer.swift`.

## 1. Thoát dấu bằng gõ đúp (Telex, VNI và phím ngoặc)

Khi lặp lại đúng tác vụ vừa thực hiện liền kề trước đó (`lastAction`), composer hoàn tác biến đổi, bật trạng thái `escapeOrigin` và giữ nguyên mọi ký tự theo sau.

| Tình huống | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Thoát thanh điệu Telex & lặp thêm | `ass`, `asss` | `as`, `ass` | `applyTone` phát hiện `lastAction == .tone`, chuyển `escapeOrigin = .telexToneConsonant` |
| Thoát gạch ngang `đ` (`d` / `9`) | `ddd`, `d99` (VNI) | `dd`, `d9` | `undoStrokeInitialD(with:)` hoàn tác `đ` → `d` + trigger gốc |
| Thoát dấu mũ, trăng, móc | `aaa`, `eee`, `uww`, `ww`, `a66` (VNI), `a11` (VNI) | `aa`, `ee`, `uw`, `w`, `a6`, `a1` | `applyShape` và nhánh `standaloneW` đặt `escapeOrigin = .explicitEscape` |
| Thoát gõ tắt ngoặc vuông | `[[a]`, `[[a]]`, `[[]` | `[a]`, `[a]]`, `[]` | Nhánh `.standaloneBracket` hoàn tác `ơ`/`ư` về `[` hoặc `]` |
| Ký tự kéo dài không cùng loại với thao tác ngay trước | `uwafaa`, `Kia2aa` (VNI), `Hoa2ii` (VNI) | `uwafaa`, `Kìaaa`, `Hoàii` | Từ chối dấu mũ/dấu sai vị trí để rơi về nguyên bản hoặc nối chữ bình thường |

## 2. Nối tiếp chuỗi sau khi escape & bảo toàn chữ hoa/thường

Sau khi `escapeOrigin != nil`, vòng lặp xử lý trong `SyllableComposer.composeResult` chép thẳng toàn bộ ký tự còn lại vào `escapedDisplay`:

| Nhóm tình huống | Chuỗi phím gõ | Kết quả | Ghi chú kỹ thuật |
| :--- | :--- | :--- | :--- |
| Escape `w` đầu từ kèm từ theo sau | `wword`, `wword `, `Wword`, `WWORD`, `wwith`, `wwas`, `wwindow` | `word`, `word `, `Word`, `WORD`, `with`, `was`, `window` | Chữ hoa của ký tự trigger đầu tiên (`W`) được bảo toàn khi render `escapedDisplay` |
| Escape `w` sau phụ âm hoặc nguyên âm | `twwo`, `swweet`, `giwwa`, `dowwn`, `towwn`, `awway`, `powwer`, `uwwa`, `uowwn`, `uuwwn` | `two`, `sweet`, `giwa`, `down`, `town`, `away`, `power`, `uwa`, `uown`, `uuwn` | Giữ cấu trúc chữ trước điểm escape và nối tiếp chuỗi sau |
| Escape `dd` và nguyên âm đôi | `dddos`, `DDdos`, `Dddos`, `teeen`, `seeen`, `EEen`, `mooon`, `goood`, `sooon` | `ddos`, `DDos`, `Ddos`, `teen`, `seen`, `EEn`, `moon`, `good`, `soon` | Giữ đúng trạng thái hoa/thường tại hai ký tự `d` đầu |
| Escape trong VNI kèm hậu tố chữ | `d99os`, `a66n`, `a11b` | `d9os`, `a6n`, `a1b` | Kết hợp phím số làm trigger và chữ cái theo sau |
| Backspace ngay trên từ vừa escape | `wword<BS>k`, `dddo<BS>`, `ddd<BS>`, `aaa<BS>`, `ass<BS>`, `passsword` | `work`, `dd`, `d`, `a`, `a`, `password` | `VietInputEngine.handleBackspace` nhận biết `currentResult.isEscaped` để cắt `rawKeys` đồng bộ |

## 3. Phân giải từ phụ âm đơn vs phụ âm kép tiếng Anh

Với trigger thanh điệu Telex (`telexToneConsonant`), ví dụ gõ `dessign` (có thể là người dùng gõ đúp để thoát dấu cho `design`, cũng có thể là từ thực sự có phụ âm kép như `password`), `shouldRestoreGeminateToneWord` phân giải bằng `NSSpellChecker`:

| Nhóm | Chuỗi phím gõ | Kết quả | Cơ chế quyết định |
| :--- | :--- | :--- | :--- |
| Từ tiếng Anh phụ âm đơn được gõ escape | `dessign`, `dessignSystem`, `losse`, `usser`, `ressult`, `masster`, `passtor`, `assk`, `reffer`, `deffine`, `beffore`, `corre`, `carre`, `charrs`, `basses`, `mousse`, `posse`, `dessert` | `design`, `designSystem`, `lose`, `user`, `result`, `master`, `pastor`, `ask`, `refer`, `define`, `before`, `core`, `care`, `chars`, `bases`, `mouse`, `pose`, `desert` | Ưu tiên giữ `escapedDisplay` (bản phụ âm đơn) khi từ đơn hợp lệ còn bản lặp không phải là từ kép chuẩn |
| Từ tiếng Anh phụ âm kép thực sự | `password`, `passwords`, `message`, `messages`, `coffee`, `error`, `offer`, `offering`, `traffic`, `current`, `session`, `issue`, `buffer`, `correct`, `mirror`, `borrow`, `array`, `arrow`, `sorry`, `errorCode` | `password`, `passwords`, `message`, `messages`, `coffee`, `error`, `offer`, `offering`, `traffic`, `current`, `session`, `issue`, `buffer`, `correct`, `mirror`, `borrow`, `array`, `arrow`, `sorry`, `errorCode` | Khôi phục `unconsumedRawKeys()` khi kiểm tra từ vựng xác nhận bản phụ âm kép là từ hợp lệ |
| Từ tiếng Việt thực sự có vần trùng tiếng Anh | `beef mawtj` | `bề mặt` | Không để từ điển tiếng Anh ghi đè lên âm tiết tiếng Việt hoàn chỉnh |

## 4. Từ viết tắt in hoa, số nhiều và định danh code

Các từ viết tắt lặp phím thanh điệu (ví dụ `URRL` do gõ quen hoặc bấm thừa `R`), định danh `camelCase`, `PascalCase`, `snake_case`, `kebab-case` đều đi qua cùng pipeline `splitIdentifierSubwords` và `escapeOrigin`:

| Nhóm | Chuỗi phím gõ | Kết quả | Cơ chế xử lý |
| :--- | :--- | :--- | :--- |
| Từ viết tắt in hoa & số nhiều | `URRL`, `urrl`, `URRLs`, `URRLS`, `URrL`, `URRI`, `URRIs`, `CORRS`, `BASSH`, `USSER`, `DESSIGN`, `USSSR`, `WWASM`, `CURRL` | `URL`, `url`, `URLs`, `URLS`, `URL`, `URI`, `URIs`, `CORS`, `BASH`, `USER`, `DESIGN`, `USSR`, `WASM`, `CURL` | Thoát phím lặp bảo toàn hoa/thường tại vị trí trigger, từ chối chuỗi hex 4+ ký tự giả ở `isValidEnglishWord` |
| Định danh `camelCase` & phân cách ký hiệu | `URRLSession`, `dessignSystem`, `DessignSystem`, `usserName`, `URRL_BASE`, `dessign-system`, `urrl2`, `URRL<BS>I` | `URLSession`, `designSystem`, `DesignSystem`, `userName`, `URL_BASE`, `design-system`, `url2`, `URI` | Dấu `_`, `-`, chữ số kết thúc âm tiết hiện tại; Backspace lùi chuẩn qua `URI` |
