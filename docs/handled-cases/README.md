# Danh mục các trường hợp đã xử lý trong VietGo

Thư mục này phân nhóm có cấu trúc toàn bộ các tình huống gõ tiếng Việt, thoát dấu, khôi phục tiếng Anh/URL, xử lý Backspace/con trỏ và tương thích ứng dụng macOS mà **VietGo** hiện đang xử lý và có test kiểm chứng.

## Cấu trúc thư mục

| Tập tin | Phạm vi chuyên đề | Ánh xạ mã nguồn chính | Test kiểm chứng |
| :--- | :--- | :--- | :--- |
| [01-telex-vni-syllables.md](01-telex-vni-syllables.md) | Ghép âm tiết Telex/VNI, bỏ dấu tự do, vần đặc biệt, địa danh `Đắk`/`Krông`, chữ hoa và Unicode dựng sẵn | `SyllableComposer.swift`, `VietnameseTables.swift` | `testTelexCore*`, `testFreeOrder*`, `testVNIFullCoverage`, `testTelexOaBreveAndUuHorn`, `testGiWAndTriphthongsOaoOeo`, `testUwoAndUoTransitionCases`, `testDoubleOAndCodaSyllables`, `testUppercaseAbbreviationsAndEthnicNames`, `testPrecomposedInputBracketShortcutsAndPaths`, `testStandaloneBreveCircumflexAndBackticks` |
| [02-escapes-and-disambiguation.md](02-escapes-and-disambiguation.md) | Thoát dấu phím đúp, nối tiếp chữ cái sau escape, phân giải phụ âm đơn/kép tiếng Anh, từ viết tắt & `camelCase` | `SyllableComposer.swift` (`escapeOrigin`, `shouldRestoreGeminateToneWord`) | `testDoubleKeyEscapes`, `testGlobalEscapeContinuationCaseAndBackspace`, `testTelexToneEscapeVsGeminateDisambiguation`, `testExhaustiveAcronymsCamelCaseZAndEdgeCaseMatrix` |
| [03-english-code-and-urls.md](03-english-code-and-urls.md) | Lọc âm vị học tiếng Việt, chặn hồi sinh âm tiết hỏng, cụm `wr-`, `d...d` dài, từ rút gọn `-n't`, URL & đường dẫn | `SyllableComposer.swift`, `VietInputEngine.swift`, `VietnameseTables.swift` | `testAutoRestoreEnglishAndCodeWords`, `testInvalidCircumflexElongationAndOpenAlpha`, `testDoubleTapEscapeAndOrthographyAutoRestore`, `testExpandedEdgeCasesPluralStopCodaIntermediateAndWrCluster`, `testRound3*` |
| [04-backspace-and-editing.md](04-backspace-and-editing.md) | Tối ưu LCP, Backspace sau Space/dấu câu, dịch dấu khi xóa coda, co ngắn đơn điệu, phím điều hướng & giới hạn `O(1)` | `VietInputEngine.swift` (`committedHistory`, `handleBackspace`, `makeReplaceAction`) | `testBackspaceSynchronizationAndMinimalLCP`, `testPostSpaceBackspaceAndCodaToneShift`, `testPerformanceAuditSafeguardsAndFunctionKeys`, `testRound3*`, Browser QA `R3_01`, `R3_05`, `R3_07`, `R3_10` |
| [05-macos-apps-and-eventtap.md](05-macos-apps-and-eventtap.md) | Event tap `.cghidEventTap`, chống nuốt chữ trình duyệt (`U+0259`), điều nhịp Terminal/Office, bảo vệ Secure Input & khôi phục tap | `EventTapManager.swift`, `AppSettings.swift` | Browser QA Round 1–3 (`R3_01`–`R3_12`), `scripts/validate_fast_chat_e2e.swift` |

## Quy ước đọc bảng

Mỗi bảng trong 5 tài liệu con trình bày theo cấu trúc thống nhất:
- **Nhóm / Tình huống**: Mô tả ngắn gọn quy tắc hoặc edge case.
- **Chuỗi phím mẫu**: Chuỗi keystroke thô đầu vào (`<BS>` ký hiệu Backspace, `` `...` `` giữ nguyên ASCII gốc).
- **Kết quả đầu ra**: Chuỗi Unicode NFC hiển thị sau khi xử lý.
- **Cơ chế xử lý**: Tên hàm, bảng tra hoặc flag điều khiển hành vi tương ứng trong mã nguồn.
