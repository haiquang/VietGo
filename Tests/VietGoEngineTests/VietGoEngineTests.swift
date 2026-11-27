import XCTest
@testable import VietGoEngine

final class VietGoEngineTests: XCTestCase {
    private func simulateTyping(
        _ input: String,
        config: EngineConfig = EngineConfig()
    ) -> (output: String, actions: [EngineAction]) {
        var engine = VietInputEngine(config: config)
        var screen: [Character] = []
        var actions: [EngineAction] = []

        for ch in input {
            if ch == "\u{08}" {
                let bsAction = engine.handleBackspace()
                actions.append(bsAction)
                switch bsAction {
                case .passThrough:
                    if !screen.isEmpty {
                        screen.removeLast()
                    }
                case .replace(let backspaceCount, let text):
                    let removeCount = min(backspaceCount, screen.count)
                    if removeCount > 0 {
                        screen.removeLast(removeCount)
                    }
                    screen.append(contentsOf: text)
                }
                continue
            }

            let action = engine.processKey(ch)
            actions.append(action)

            switch action {
            case .passThrough:
                screen.append(ch)
            case .replace(let backspaceCount, let text):
                let removeCount = min(backspaceCount, screen.count)
                if removeCount > 0 {
                    screen.removeLast(removeCount)
                }
                screen.append(contentsOf: text)
            }
        }

        return (String(screen).precomposedStringWithCanonicalMapping, actions)
    }

    func testTelexCoreVocabularyAndComplexSyllables() {
        let cases: [(String, String)] = [
            ("xin chaof", "xin chào"),
            ("vieetj nam", "việt nam"),
            ("tieengs vieetj", "tiếng việt"),
            ("truwowngf hocj", "trường học"),
            ("nguwowif", "người"),
            ("dduwowcj", "được"),
            ("muwowif", "mười"),
            ("ruwowuj", "rượu"),
            ("huwowu", "hươu"),
            ("gieengs", "giếng"),
            ("gieets", "giết"),
            ("giuwx", "giữ"),
            ("giuwax", "giữa"),
            ("giuwowngf", "giường"),
            ("gif", "gì"),
            ("ginf", "gìn"),
            ("gir", "gỉ"),
            ("quas", "quá"),
            ("quoocs", "quốc"),
            ("quys", "quý"),
            ("quynhf", "quỳnh"),
            ("quow", "quơ"),
            ("huow", "huơ"),
            ("thuowr", "thuở"),
            ("thuwowng", "thương"),
            ("tuyeen", "tuyên"),
            ("chuyeenj", "chuyện"),
            ("khuya", "khuya"),
            ("khuyur", "khuỷu"),
            ("ngoafi", "ngoài"),
            ("xoays", "xoáy"),
            ("xooong", "xoong")
        ]

        for (input, expected) in cases {
            let result = simulateTyping(input).output
            XCTAssertEqual(result, expected, "Failed for Telex input: \(input)")
        }
    }

    func testFreeOrderToneAndModifierPlacement() {
        let cases: [(String, String)] = [
            ("truongwf", "trường"),
            ("truwowngf", "trường"),
            ("truwongf", "trường"),
            ("nguoiwf", "người"),
            ("nguwowif", "người"),
            ("duocdwj", "được"),
            ("dduwowcj", "được"),
            ("vietej", "việt"),
            ("chuanar", "chuẩn"),
            ("nhw", "như"),
            ("wf", "ừ"),
            ("giuongwf", "giường"),
            ("dangd", "đang")
        ]

        for (input, expected) in cases {
            let result = simulateTyping(input).output
            XCTAssertEqual(result, expected, "Failed for free-order input: \(input)")
        }
    }

    func testToneSwitchingAndRemoval() {
        XCTAssertEqual(simulateTyping("as").output, "á")
        XCTAssertEqual(simulateTyping("asf").output, "à")
        XCTAssertEqual(simulateTyping("asfz").output, "a")
        XCTAssertEqual(simulateTyping("tiengs").output, "tiéng")
        XCTAssertEqual(simulateTyping("tieengs").output, "tiếng")
        XCTAssertEqual(simulateTyping("tieengsz").output, "tiêng")
    }

    func testDoubleKeyEscapes() {
        let cases: [(String, String)] = [
            ("ass", "as"),
            ("asss", "ass"),
            ("ddd", "dd"),
            ("aaa", "aa"),
            ("eee", "ee"),
            ("uww", "uw"),
            ("ww", "w")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed double-key escape: \(input)")
        }
    }

    func testVNIFullCoverage() {
        let vniConfig = EngineConfig(inputMethod: .vni)
        let cases: [(String, String)] = [
            ("xin cha2o vie65t nam", "xin chào việt nam"),
            ("tru7o72ng", "trường"),
            ("truong72", "trường"),
            ("d9u7o75c", "được"),
            ("a10", "a"),
            ("a11", "a1"),
            ("d99", "d9"),
            ("a66", "a6"),
            ("ho3i", "hỏi"),
            ("nguo72i", "người"),
            ("vie65t", "việt")
        ]

        for (input, expected) in cases {
            let result = simulateTyping(input, config: vniConfig).output
            XCTAssertEqual(result, expected, "Failed for VNI input: \(input)")
        }
    }

    func testTonePlacementStyles() {
        let modern = EngineConfig(inputMethod: .telex, toneStyle: .modern)
        XCTAssertEqual(simulateTyping("hoaf", config: modern).output, "h\u{00F2}a")
        XCTAssertEqual(simulateTyping("khoer", config: modern).output, "kh\u{1ECF}e")
        XCTAssertEqual(simulateTyping("thuyr", config: modern).output, "th\u{1EE7}y")
        XCTAssertEqual(simulateTyping("tuyf", config: modern).output, "t\u{00F9}y")
        XCTAssertEqual(simulateTyping("toans", config: modern).output, "to\u{00E1}n")

        let traditional = EngineConfig(inputMethod: .telex, toneStyle: .traditional)
        XCTAssertEqual(simulateTyping("hoaf", config: traditional).output, "ho\u{00E0}")
        XCTAssertEqual(simulateTyping("khoer", config: traditional).output, "kho\u{1EBB}")
        XCTAssertEqual(simulateTyping("thuyr", config: traditional).output, "thu\u{1EF7}")
        XCTAssertEqual(simulateTyping("tuyf", config: traditional).output, "tu\u{1EF3}")
        XCTAssertEqual(simulateTyping("toans", config: traditional).output, "to\u{00E1}n")
    }

    func testAutoRestoreEnglishAndCodeWords() {
        let words = [
            "window", "refresh", "string", "git", "claude", "swift",
            "text", "next", "left", "soft", "port", "sort",
            "part", "cart", "start", "chart", "fork", "work",
            "mark", "curl", "word", "self", "function", "fix",
            "json", "zip", "web", "wifi", "testing", "variable",
            "tests", "hosts", "lists", "class", "press", "staff",
            "bugs", "items", "apps", "books"
        ]

        for word in words {
            let result = simulateTyping(word).output
            XCTAssertEqual(result, word, "Failed auto-restore for word: \(word)")
        }

        let sentence = simulateTyping("tooi ddang dungf swift trong window").output
        XCTAssertEqual(sentence, "tôi đang dùng swift trong window")
    }

    func testCasePreservation() {
        let cases: [(String, String)] = [
            ("Vieetj", "Việt"),
            ("VIEETJ", "VIỆT"),
            ("Ddaf Nawngx", "Đà Nẵng"),
            ("DDAF NAWNGX", "ĐÀ NẴNG"),
            ("Window", "Window"),
            ("STRING", "STRING"),
            ("Refresh", "Refresh")
        ]

        for (input, expected) in cases {
            let result = simulateTyping(input).output
            XCTAssertEqual(result, expected, "Failed case preservation: \(input)")
        }
    }

    func testBackspaceSynchronizationAndMinimalLCP() {
        let bsResult = simulateTyping("tieengs\u{08}\u{08}p").output
        XCTAssertEqual(bsResult, "tiếp")

        var engine = VietInputEngine()
        for ch in "tieeng" {
            _ = engine.processKey(ch)
        }
        XCTAssertEqual(engine.currentWord, "tiêng")

        let action = engine.processKey("s")
        XCTAssertEqual(action, .replace(backspaceCount: 3, text: "ếng"))
    }

    // MARK: - Issue-Audit Regression Suites

    func testTelexOaBreveAndUuHorn() {
        // phatMT97/VKey#278, #213
        XCTAssertEqual(simulateTyping("thoangws").output, "thoắng")
        XCTAssertEqual(simulateTyping("thoawngs").output, "thoắng")
        XCTAssertEqual(simulateTyping("thoawsng").output, "thoắng")
        XCTAssertEqual(simulateTyping("hoawcj").output, "hoặc")
        XCTAssertEqual(simulateTyping("xoawn").output, "xoăn")

        // khaphanspace/gonhanh.org#172, ZeroX-DG/vi-rs#13, phatMT97/VKey#56
        XCTAssertEqual(simulateTyping("uuw").output, "ưu")
        XCTAssertEqual(simulateTyping("cuuws").output, "cứu")
        XCTAssertEqual(simulateTyping("cuuwf").output, "cừu")
        XCTAssertEqual(simulateTyping("luuw").output, "lưu")
        XCTAssertEqual(simulateTyping("huuw").output, "hưu")
        XCTAssertEqual(simulateTyping("cuu71", config: EngineConfig(inputMethod: .vni)).output, "cứu")
    }

    func testGiWAndTriphthongsOaoOeo() {
        // huytd/goxkey#77, phatMT97/VKey#47
        XCTAssertEqual(simulateTyping("giw").output, "giư")
        XCTAssertEqual(simulateTyping("giwx").output, "giữ")
        XCTAssertEqual(simulateTyping("giwa").output, "giưa")
        XCTAssertEqual(simulateTyping("giwax").output, "giữa")

        // huytd/goxkey#68
        XCTAssertEqual(simulateTyping("khoeof").output, "khoèo")
        XCTAssertEqual(simulateTyping("ngoaos").output, "ngoáo")

        // BoGoEngine/bogo-python#5
        XCTAssertEqual(simulateTyping("gyaj").output, "gỵa")
    }

    func testUwoAndUoTransitionCases() {
        // tuyenvm/OpenKey#133, phatMT97/VKey#18
        XCTAssertEqual(simulateTyping("khuow").output, "khuơ")
        XCTAssertEqual(simulateTyping("khuowr").output, "khuở")

        // huytd/goxkey#67
        XCTAssertEqual(simulateTyping("truwow").output, "trươ")
        XCTAssertEqual(simulateTyping("truwo").output, "trươ")
        XCTAssertEqual(simulateTyping("nguwowi").output, "ngươi")

        // xmannv/xkey#150, phatMT97/VKey#270
        XCTAssertEqual(simulateTyping("truoonw").output, "trươn")
        XCTAssertEqual(simulateTyping("truwongo").output, "truông")
        XCTAssertEqual(simulateTyping("cuowoi").output, "cuôi")
        XCTAssertEqual(simulateTyping("truowo").output, "truô")
    }

    func testDoubleOAndCodaSyllables() {
        // tuyenvm/OpenKey#41, LotusInputMethod/fcitx5-lotus#521
        XCTAssertEqual(simulateTyping("vooocj").output, "voọc")
        XCTAssertEqual(simulateTyping("sooocs").output, "soóc")
        XCTAssertEqual(simulateTyping("Thooongf").output, "Thoòng")
        XCTAssertEqual(simulateTyping("thooongf").output, "thoòng")
        XCTAssertEqual(simulateTyping("looongf").output, "loòng")
    }

    func testUppercaseAbbreviationsAndEthnicNames() {
        // tuyenvm/OpenKey#48, xmannv/xkey#299
        XCTAssertEqual(simulateTyping("SDDT").output, "SĐT")
        XCTAssertEqual(simulateTyping("QDD").output, "QĐ")
        XCTAssertEqual(simulateTyping("NDD").output, "NĐ")
        XCTAssertEqual(simulateTyping("DdL").output, "ĐL")
        XCTAssertEqual(simulateTyping("DdN").output, "ĐN")

        // tuyenvm/OpenKey#134, PhamHungTien/PHTV#135
        XCTAssertEqual(simulateTyping("Ddawsk Lawsk").output, "Đắk Lắk")
        XCTAssertEqual(simulateTyping("Ddawks Lawks").output, "Đắk Lắk")
        XCTAssertEqual(simulateTyping("Kroong Buks").output, "Krông Búk")
    }

    func testPrecomposedInputBracketShortcutsAndPaths() {
        // BoGoEngine/bogo-python#17, #19
        XCTAssertEqual(simulateTyping("TƯ2", config: EngineConfig(inputMethod: .vni)).output, "TỪ")
        XCTAssertEqual(simulateTyping("mèoj").output, "mẹo")

        // khaphanspace/gonhanh.org#159, #408
        let bracketConfig = EngineConfig(inputMethod: .telex, bracketShortcuts: true)
        XCTAssertEqual(simulateTyping("h[", config: bracketConfig).output, "hơ")
        XCTAssertEqual(simulateTyping("h]", config: bracketConfig).output, "hư")
        XCTAssertEqual(simulateTyping("~/w").output, "~/w")
        XCTAssertEqual(simulateTyping("foo/w").output, "foo/w")
        XCTAssertEqual(simulateTyping("a.w").output, "a.w")
    }

    func testInvalidCircumflexElongationAndOpenAlpha() {
        // xmannv/xkey#19, PHTV#12 (chuwaa -> chưaa without invalid ưâ, while tuaanf -> tuần still works)
        let noAutoRestore = EngineConfig(inputMethod: .telex, autoRestoreEnglish: false)
        XCTAssertEqual(simulateTyping("chuwaa", config: noAutoRestore).output, "chưaa")
        XCTAssertEqual(simulateTyping("tuaanf").output, "tuần")
        XCTAssertEqual(simulateTyping("zas", config: noAutoRestore).output, "zá")

        // xmannv/xkey#294
        XCTAssertEqual(simulateTyping("uwafaa").output, "uwafaa")

        // phatMT97/VKey#58, #268
        let vniConfig = EngineConfig(inputMethod: .vni)
        XCTAssertEqual(simulateTyping("Kia2aa", config: vniConfig).output, "Kìaaa")
        XCTAssertEqual(simulateTyping("Hoa2ii", config: vniConfig).output, "Hoàii")
        XCTAssertEqual(simulateTyping("ddaxa ").output, "ddaxa ")
    }

    func testDoubleTapEscapeAndOrthographyAutoRestore() {
        // xmannv/xkey#94, #334, #339, #64, #158
        // khaphanspace/gonhanh.org#15, #26, #403
        // PhamHungTien/PHTV#106, LotusInputMethod/fcitx5-lotus#42
        let englishWords = [
            "password", "message", "coffee", "error", "offer",
            "traffic", "current", "queue", "queues",
            "music", "basic", "coins", "pains", "trains", "suits",
            "vaixn", "buaxn", "nghaix", "nghoo", "gho", "kar", "giis",
            "gets", "ghost", "nginx", "data", "term", "more", "post",
            "cursor", "useEffect"
        ]
        for word in englishWords {
            XCTAssertEqual(simulateTyping(word).output, word, "Failed English auto-restore for: \(word)")
        }

        // Preserve real Vietnamese word "bề" (not overridden by English "beef")
        XCTAssertEqual(simulateTyping("beef mawtj").output, "bề mặt")
    }

    func testPostSpaceBackspaceAndCodaToneShift() {
        // tuyenvm/OpenKey#7, #23, huytd/goxkey#22, BambooEngine/ibus-bamboo#48, #359, fcitx5-lotus#366, VKey#281
        XCTAssertEqual(simulateTyping("co \u{08}s").output, "có")
        XCTAssertEqual(simulateTyping("tieeng \u{08}s").output, "tiếng")
        XCTAssertEqual(simulateTyping("nhu \u{08}w").output, "như")
        XCTAssertEqual(simulateTyping("bong,\u{08}s").output, "bóng")
        XCTAssertEqual(simulateTyping("hoa \u{08}f").output, "hòa")
        XCTAssertEqual(simulateTyping("go go\u{08}\u{08}\u{08}x").output, "gõ")

        // tuyenvm/OpenKey#70 (coda deletion shifts tone from `hoàn` -> `hòa`, `khoẻn` -> `khỏe`)
        XCTAssertEqual(simulateTyping("hoafn\u{08}").output, "hòa")
        XCTAssertEqual(simulateTyping("khoern\u{08}").output, "khỏe")

        // xmannv/xkey#174 (deleting trailing redundant tone key restores recomposed Vietnamese word)
        XCTAssertEqual(simulateTyping("nhaafmf\u{08}").output, "nhầm")
    }

    func testStandaloneBreveCircumflexAndBackticks() {
        // Standalone `â` / `ă` inside backticks or followed by Space
        XCTAssertEqual(simulateTyping("`aa`").output, "`â`")
        XCTAssertEqual(simulateTyping("`aw`").output, "`ă`")
        XCTAssertEqual(simulateTyping("`AA`").output, "`Â`")
        XCTAssertEqual(simulateTyping("`AW`").output, "`Ă`")
        XCTAssertEqual(simulateTyping("aa ").output, "â ")
        XCTAssertEqual(simulateTyping("aw ").output, "ă ")
        XCTAssertEqual(simulateTyping("`aas`").output, "`ấ`")
        XCTAssertEqual(simulateTyping("`aaf`").output, "`ầ`")

        let vniConfig = EngineConfig(inputMethod: .vni)
        XCTAssertEqual(simulateTyping("`a6`", config: vniConfig).output, "`â`")
        XCTAssertEqual(simulateTyping("`a8`", config: vniConfig).output, "`ă`")

        // Double-tap escapes inside backticks
        XCTAssertEqual(simulateTyping("`aaa`").output, "`aa`")
        XCTAssertEqual(simulateTyping("`aww`").output, "`aw`")

        // Auto-restore regressions preserved
        XCTAssertEqual(simulateTyping("ddaxa ").output, "ddaxa ")
        XCTAssertEqual(simulateTyping("law ").output, "law ")
        XCTAssertEqual(simulateTyping("saw ").output, "saw ")
        XCTAssertEqual(simulateTyping("raw ").output, "raw ")
        XCTAssertEqual(simulateTyping("NASA ").output, "NASA ")
        XCTAssertEqual(simulateTyping("AWS ").output, "AWS ")
        XCTAssertEqual(simulateTyping("`AWS`").output, "`AWS`")
        XCTAssertEqual(simulateTyping("asa ").output, "asa ")
    }

    func testGlobalEscapeContinuationCaseAndBackspace() {
        // Standalone & post-consonant `w` escapes + case preservation
        let wEscapeCases: [(String, String)] = [
            ("wword", "word"),
            ("wword ", "word "),
            ("Wword", "Word"),
            ("WWORD", "WORD"),
            ("wwith", "with"),
            ("wwas", "was"),
            ("wwindow", "window"),
            ("twwo", "two"),
            ("swweet", "sweet"),
            ("giwwa", "giwa")
        ]
        for (input, expected) in wEscapeCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed w-escape case: \(input)")
        }

        // Shape, circumflex, stroke escapes with trailing characters
        let shapeAndStrokeCases: [(String, String)] = [
            ("dowwn", "down"),
            ("towwn", "town"),
            ("awway", "away"),
            ("powwer", "power"),
            ("uwwa", "uwa"),
            ("uowwn", "uown"),
            ("uuwwn", "uuwn"),
            ("dddos", "ddos"),
            ("DDdos", "DDos"),
            ("Dddos", "Ddos"),
            ("teeen", "teen"),
            ("seeen", "seen"),
            ("EEen", "EEn"),
            ("baaar", "baar"),
            ("mooon", "moon"),
            ("goood", "good"),
            ("sooon", "soon"),
            ("food", "food")
        ]
        for (input, expected) in shapeAndStrokeCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed shape/stroke escape: \(input)")
        }

        // VNI and bracket-shortcut escapes with trailing characters
        let vniConfig = EngineConfig(inputMethod: .vni)
        XCTAssertEqual(simulateTyping("d99os", config: vniConfig).output, "d9os")
        XCTAssertEqual(simulateTyping("a66n", config: vniConfig).output, "a6n")
        XCTAssertEqual(simulateTyping("a11b", config: vniConfig).output, "a1b")

        let bracketConfig = EngineConfig(inputMethod: .telex, bracketShortcuts: true)
        XCTAssertEqual(simulateTyping("[[a]", config: bracketConfig).output, "[a]")
        XCTAssertEqual(simulateTyping("[[a]]", config: bracketConfig).output, "[a]]")
        XCTAssertEqual(simulateTyping("[[]", config: bracketConfig).output, "[]")

        // Path & URL prefixes keep full literal token after `w`
        XCTAssertEqual(simulateTyping("~/was ").output, "~/was ")
        XCTAssertEqual(simulateTyping("a.wav").output, "a.wav")
        XCTAssertEqual(simulateTyping("https://www.google.com").output, "https://www.google.com")

        // Backspace preserves escaped state & handles triple-repeat tone escape
        XCTAssertEqual(simulateTyping("wword\u{08}k").output, "work")
        XCTAssertEqual(simulateTyping("dddo\u{08}").output, "dd")
        XCTAssertEqual(simulateTyping("ddd\u{08}").output, "d")
        XCTAssertEqual(simulateTyping("aaa\u{08}").output, "a")
        XCTAssertEqual(simulateTyping("ass\u{08}").output, "a")
        XCTAssertEqual(simulateTyping("passsword").output, "password")
    }

    func testTelexToneEscapeVsGeminateDisambiguation() {
        // Escaped single-consonant words & typos stay single-consonant (never jump to double consonant)
        let singleConsonantEscapes: [(String, String)] = [
            ("dessign", "design"),
            ("dessign ", "design "),
            ("dessigne", "designe"),
            ("dessigner", "designer"),
            ("dessignSystem", "designSystem"),
            ("losse", "lose"),
            ("usser", "user"),
            ("ressult", "result"),
            ("masster", "master"),
            ("passtor", "pastor"),
            ("assk", "ask"),
            ("reffer", "refer"),
            ("deffine", "define"),
            ("beffore", "before"),
            ("corre", "core"),
            ("carre", "care"),
            ("share", "share")
        ]
        for (input, expected) in singleConsonantEscapes {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed single-consonant escape: \(input)")
        }

        // Genuine double-consonant English words & inflections still restore cleanly
        let geminateWords: [String] = [
            "password", "passwords", "message", "messages", "coffee",
            "error", "offer", "offering", "traffic", "current", "errorCode"
        ]
        for word in geminateWords {
            XCTAssertEqual(simulateTyping(word).output, word, "Failed geminate restore: \(word)")
        }
    }

    func testExhaustiveAcronymsCamelCaseZAndEdgeCaseMatrix() {
        let cases: [(String, String)] = [
            // ALL-CAPS, mixed-case, and plural acronyms with escaped Telex tone keys
            ("URRL", "URL"),
            ("urrl", "url"),
            ("URRLs", "URLs"),
            ("URRLS", "URLS"),
            ("URrL", "URL"),
            ("UrRL", "UrL"),
            ("URRI", "URI"),
            ("URRIs", "URIs"),
            ("URRN", "URN"),
            ("ORRM", "ORM"),
            ("ARRG", "ARG"),
            ("ARRGS", "ARGS"),
            ("VARR", "VAR"),
            ("DEFF", "DEF"),
            ("REFF", "REF"),
            ("DIRR", "DIR"),
            ("RESS", "RES"),
            ("POSS", "POS"),
            ("USSR", "USR"),
            ("ussr", "usr"),
            ("USSSR", "USSR"),
            ("CORRS", "CORS"),
            ("WASM", "WASM"),
            ("WWASM", "WASM"),
            ("CURRL", "CURL"),
            ("BASSH", "BASH"),
            ("JSON", "JSON"),
            ("URL", "URL"),
            ("AFFC", "AFC"),
            ("USSER", "USER"),
            ("DESSIGN", "DESIGN"),
            ("Dessign", "Design"),

            // CamelCase & PascalCase identifiers
            ("URRLSession", "URLSession"),
            ("dessignSystem", "designSystem"),
            ("DessignSystem", "DesignSystem"),
            ("usserName", "userName"),
            ("errorCode", "errorCode"),
            ("ErrorCode", "ErrorCode"),
            ("errorMessage", "errorMessage"),
            ("currentUser", "currentUser"),

            // Minimal-pair tie-breakers: preserve valid escaped single-consonant words
            ("charrs", "chars"),
            ("basses", "bases"),
            ("mousse", "mouse"),
            ("posse", "pose"),
            ("dessert", "desert"),
            ("desert", "desert"),

            // Geminate English words across casing variants
            ("Password", "Password"),
            ("PASSWORD", "PASSWORD"),
            ("MESSAGE", "MESSAGE"),
            ("COFFEE", "COFFEE"),
            ("ERROR", "ERROR"),
            ("OFFER", "OFFER"),
            ("OFFERING", "OFFERING"),
            ("TRAFFIC", "TRAFFIC"),
            ("CURRENT", "CURRENT"),
            ("SESSION", "SESSION"),
            ("ISSUE", "ISSUE"),
            ("BUFFER", "BUFFER"),
            ("CORRECT", "CORRECT"),
            ("MIRROR", "MIRROR"),
            ("BORROW", "BORROW"),
            ("ARRAY", "ARRAY"),
            ("ARROW", "ARROW"),
            ("SORRY", "SORRY"),

            // `z` after invalid stop-coda tone vs valid Vietnamese `z` removal
            ("quartz", "quartz"),
            ("QUARTZ", "QUARTZ"),
            ("hertz", "hertz"),
            ("HERTZ", "HERTZ"),
            ("wartz", "wartz"),
            ("asfz", "a"),
            ("tieengsz", "tiêng"),
            ("hoafz", "hoa"),

            // Invalid Vietnamese onsets + `w` escapes
            ("fww", "fww"),
            ("jww", "jww"),
            ("qww", "qww"),
            ("qwerty", "qwerty"),

            // Delimiters & Backspace on escaped acronyms
            ("URRL_BASE", "URL_BASE"),
            ("dessign-system", "design-system"),
            ("urrl2", "url2"),
            ("URRL\u{08}I", "URI")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed edge case matrix: \(input)")
        }
    }

    func testPerformanceAuditSafeguardsAndFunctionKeys() {
        // 1. Control & macOS PUA function keys (F1..F20, Escape, Delete) must pass through cleanly without replacing
        var engine = VietInputEngine()
        XCTAssertEqual(engine.processKey("t"), .passThrough)
        XCTAssertEqual(engine.processKey("u"), .passThrough)

        for key in [Character("\u{F704}"), Character("\u{F708}"), Character("\u{F70F}"), Character("\u{001B}"), Character("\u{007F}")] {
            var localEngine = VietInputEngine()
            _ = localEngine.processKey("a")
            let action = localEngine.processKey(key)
            XCTAssertEqual(action, .passThrough, "Expected control/PUA key to passThrough")
            XCTAssertEqual(localEngine.currentWord, "", "Expected control/PUA key to reset currentWord")
        }

        // 2. Trailing displayed helpers without array allocation
        var helperEngine = VietInputEngine()
        for ch in "ys" {
            _ = helperEngine.processKey(ch)
        }
        XCTAssertEqual(helperEngine.lastDisplayedCharacter, "ý")
        XCTAssertEqual(helperEngine.countTrailingDisplayed(maxCount: 1, where: { $0 == "ý" || $0 == "Ý" }), 1)
        XCTAssertEqual(helperEngine.countTrailingDisplayed(maxCount: 2, where: { $0 == "t" }), 0)

        // 3. Long tokens (>48 chars) and pathological inputs complete in < 20ms without quadratic spike
        let longNonViet = String(repeating: "c", count: 1) + String(repeating: "i", count: 2) + String(repeating: "f", count: 80)
        let longRandom = String(repeating: "x", count: 120)

        let start = CFAbsoluteTimeGetCurrent()
        _ = simulateTyping(longNonViet)
        _ = simulateTyping(longRandom)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        XCTAssertLessThan(elapsedMs, 20.0, "Long-token composition exceeded 20ms latency budget: \(elapsedMs)ms")
    }

    func testPlainVowelDiphthongAndFreeOrderTonePlacement() {
        let cases: [(String, String)] = [
            ("cuar", "của"),
            ("cura", "của"),
            ("taij", "tại"),
            ("taji", "tại"),
            ("hanfh", "hành"),
            ("hafnh", "hành"),
            ("hanhf", "hành"),
            ("xem taij sao", "xem tại sao"),
            ("UI cuar app", "UI của app"),
            ("`cuar` `taij`", "`của` `tại`"),
            ("loaij", "loại"),
            ("ngoaij", "ngoại"),
            ("muar", "mủa"),
            ("buooir", "buổi"),
            ("toir", "tỏi"),
            ("lamf", "làm"),
            ("ddax", "đã"),
            ("mowis", "mới")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed diphthong/free-order tone: \(input)")
        }
    }

    func testFastChatUserRegressionSentences() {
        let cases: [(String, String)] = [
            (
                "looix quas nhieeuf sau fix, ddanhs gias laij xem, banj thuwr validation nhuw mootj nguowif dungf chat nhanh ddi",
                "lỗi quá nhiều sau fix, đánh giá lại xem, bạn thử validation như một người dùng chat nhanh đi"
            ),
            ("ddasnh", "đánh"),
            ("thuwr ", "thử "),
            ("dungf chat", "dùng chat"),
            ("ddi", "đi"),
            ("lamf", "làm"),
            ("ddax", "đã"),
            ("cuar", "của"),
            ("taij", "tại"),
            ("hanfh", "hành"),
            ("mowis ", "mới ")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed fast-chat regression: \(input)")
        }
    }

    func testExpandedEdgeCasesPluralStopCodaIntermediateAndWrCluster() {
        // 1. Dead syllable must never resurrect on a subsequent tone key (`texts`, `sorts`, `nextjs`, etc.)
        let pluralAndFrameworkWords = [
            "texts", "sorts", "ports", "parts", "carts", "darts",
            "softs", "lofts", "rafts", "lifts", "gifts",
            "nextjs", "nuxtjs"
        ]
        for word in pluralAndFrameworkWords {
            XCTAssertEqual(simulateTyping(word).output, word, "Failed dead-syllable guard for: \(word)")
            XCTAssertEqual(simulateTyping(word + " ").output, word + " ", "Failed finalized word for: \(word)")
        }

        // 2. Unresolved intermediate nuclei restore on word finalization, while mid-word typing still composes
        let finalizedIntermediateCases: [(String, String)] = [
            ("lieus ", "lieus "),
            ("milieus ", "milieus "),
            ("cuois ", "cuois "),
            ("ruous ", "ruous "),
            ("tuois ", "tuois "),
            ("tuyetj ", "tuyetj "),
            ("ddien ", "ddien "),
            ("tiengs", "tiéng"),
            ("vietej ", "việt "),
            ("truongwf ", "trường "),
            ("nhieufe ", "nhiều ")
        ]
        for (input, expected) in finalizedIntermediateCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed intermediate nucleus case: \(input)")
        }

        // 3. English `wr-` + vowel cluster rejects standalone `ư`, while keeping `wr` / `wf` / `uowngr`
        let wrCases: [(String, String)] = [
            ("wrong", "wrong"),
            ("wrong ", "wrong "),
            ("wrongs", "wrongs"),
            ("wrongs ", "wrongs "),
            ("write", "write"),
            ("wrap", "wrap"),
            ("wr ", "ử "),
            ("wf ", "ừ "),
            ("uowngr ", "ưởng ")
        ]
        for (input, expected) in wrCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed wr- cluster case: \(input)")
        }
    }

    func testRound3BackspaceMonotonicityContractionsURLsAndDegreeDefend() {
        // 1. Backspace strictly shrinks intermediate-nucleus words without raw-key explosion
        var bsEngine = VietInputEngine(config: EngineConfig(inputMethod: .telex))
        var bsBuffer: [Character] = []
        for ch in "tiengs" {
            switch bsEngine.processKey(ch) {
            case .passThrough:
                bsBuffer.append(ch)
            case .replace(let bs, let text):
                bsBuffer.removeLast(min(bs, bsBuffer.count))
                bsBuffer.append(contentsOf: text)
            }
        }
        XCTAssertEqual(String(bsBuffer), "tiéng")

        let expectedShrinkSteps = ["tién", "tié", "ti", "t", ""]
        for expectedAfterBS in expectedShrinkSteps {
            let prevCount = bsBuffer.count
            switch bsEngine.handleBackspace() {
            case .passThrough:
                if !bsBuffer.isEmpty { bsBuffer.removeLast() }
            case .replace(let bs, let text):
                bsBuffer.removeLast(min(bs + 1, bsBuffer.count))
                bsBuffer.append(contentsOf: text)
            }
            XCTAssertEqual(String(bsBuffer), expectedAfterBS)
            XCTAssertLessThan(bsBuffer.count, prevCount, "Backspace must strictly shrink text length")
        }

        // Recovering via Backspace then finishing the intended Vietnamese word (`tiếng`)
        var recoverEngine = VietInputEngine(config: EngineConfig(inputMethod: .telex))
        var recoverBuf: [Character] = []
        for ch in "tiens" {
            switch recoverEngine.processKey(ch) {
            case .passThrough: recoverBuf.append(ch)
            case .replace(let bs, let text):
                recoverBuf.removeLast(min(bs, recoverBuf.count))
                recoverBuf.append(contentsOf: text)
            }
        }
        XCTAssertEqual(String(recoverBuf), "tién")
        for _ in 0..<2 {
            switch recoverEngine.handleBackspace() {
            case .passThrough: if !recoverBuf.isEmpty { recoverBuf.removeLast() }
            case .replace(let bs, let text):
                recoverBuf.removeLast(min(bs + 1, recoverBuf.count))
                recoverBuf.append(contentsOf: text)
            }
        }
        XCTAssertEqual(String(recoverBuf), "ti")
        for ch in "eengs " {
            switch recoverEngine.processKey(ch) {
            case .passThrough: recoverBuf.append(ch)
            case .replace(let bs, let text):
                recoverBuf.removeLast(min(bs, recoverBuf.count))
                recoverBuf.append(contentsOf: text)
            }
        }
        XCTAssertEqual(String(recoverBuf), "tiếng ")

        // 2. Invalid coda & dead-syllable shape escape (`degree`, `decree`) + long-distance d...d (`defend`, `defends`)
        let englishCases: [(String, String)] = [
            ("degree ", "degree "),
            ("decree ", "decree "),
            ("defend ", "defend "),
            ("defends ", "defends "),
            ("depend ", "depend "),
            ("world ", "world "),
            ("duowngd ", "đương "),
            ("ddeenf ", "đền "),
            ("ddeens ", "đến ")
        ]
        for (input, expected) in englishCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed case: \(input)")
        }

        // 3. English `-n't` contractions followed by Vietnamese
        let contractionCases: [(String, String)] = [
            ("doesn't work ", "doesn't work "),
            ("isn't it ", "isn't it "),
            ("won't fail ", "won't fail "),
            ("hasn't changed ", "hasn't changed "),
            ("It doesn't work, nhuwng tooi vaanx passes ", "It doesn't work, nhưng tôi vẫn passes ")
        ]
        for (input, expected) in contractionCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed contraction case: \(input)")
        }

        // 4. URLs (*://...) and home paths (~/...) keep every segment literal, while `anh/chij` still works
        let urlCases: [(String, String)] = [
            ("https://docs.google.com/forms tieeps ", "https://docs.google.com/forms tiếp "),
            ("http://localhost:3000/test moiw ", "http://localhost:3000/test mơi "),
            ("~/Works/test/forms dduowcj ", "~/Works/test/forms được "),
            ("cd ~/Works/was/test lafm ", "cd ~/Works/was/test làm "),
            ("anh/chij ", "anh/chị ")
        ]
        for (input, expected) in urlCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed URL/path case: \(input)")
        }
    }

    func testRound4ParagraphBackspaceEnglishGeminatesAndWCombinations() {
        // 1. Long mixed Vietnamese + English paragraph: typing then deleting EVERY character backward
        // must shrink monotonically by exact 1 char per step with zero jumps or English mutations.
        let paragraphInput = "Hoom nay tooi kieemr tra booj gox VietGo vowis nhieeuf twf tieengs Anh nhw window refresh defend texts tests work virus away less boss yess was war won worm ddwocj giwx nguyen khong nhayr chuwx! "
        let expectedParagraph = "Hôm nay tôi kiểm tra bộ gõ VietGo với nhiều từ tiếng Anh như window refresh defend texts tests work virus away less boss yess was war won worm được giữ nguyen khong nhảy chữ! "

        var engine = VietInputEngine()
        var screen: [Character] = []
        for ch in paragraphInput {
            switch engine.processKey(ch) {
            case .passThrough:
                screen.append(ch)
            case .replace(let bs, let text):
                screen.removeLast(min(bs, screen.count))
                screen.append(contentsOf: text)
            }
        }
        XCTAssertEqual(String(screen).precomposedStringWithCanonicalMapping, expectedParagraph)

        // Protect every English token range against non-trivial backspace mutation
        let fullStr = String(screen).precomposedStringWithCanonicalMapping
        let protectedEnglish = [
            "VietGo", "window", "refresh", "defend", "texts", "tests",
            "work", "virus", "away", "less", "boss", "yess", "was", "war", "won", "worm"
        ]
        var protectedRanges: [Range<Int>] = []
        for token in protectedEnglish {
            if let r = fullStr.range(of: token) {
                let start = fullStr.distance(from: fullStr.startIndex, to: r.lowerBound)
                let end = fullStr.distance(from: fullStr.startIndex, to: r.upperBound)
                protectedRanges.append((start + 1)..<(end + 1))
            }
        }

        while !screen.isEmpty {
            let prevScreen = screen
            switch engine.handleBackspace() {
            case .passThrough:
                screen.removeLast()
            case .replace(let bs, let text):
                screen.removeLast(min(bs, screen.count))
                screen.append(contentsOf: text)
            }
            XCTAssertEqual(
                screen.count,
                prevScreen.count - 1,
                "Backspace jumped/expanded: '\(String(prevScreen))' -> '\(String(screen))'"
            )
            if protectedRanges.contains(where: { $0.contains(prevScreen.count) }) {
                XCTAssertEqual(
                    String(screen),
                    String(prevScreen.dropLast()),
                    "English token mutated during Backspace: '\(String(prevScreen))' -> '\(String(screen))'"
                )
            }
        }
        XCTAssertEqual(String(screen), "")

        // Held Backspace autorepeat mode (`allowToneReposition: false`) never emits synthetic replacement on coda deletion
        var repeatEngine = VietInputEngine()
        var repeatScreen: [Character] = []
        for ch in "hoafn" {
            switch repeatEngine.processKey(ch) {
            case .passThrough:
                repeatScreen.append(ch)
            case .replace(let bs, let text):
                repeatScreen.removeLast(min(bs, repeatScreen.count))
                repeatScreen.append(contentsOf: text)
            }
        }
        XCTAssertEqual(String(repeatScreen), "hoàn")
        let repeatBS = repeatEngine.handleBackspace(allowToneReposition: false)
        XCTAssertEqual(repeatBS, .passThrough)
        repeatScreen.removeLast()
        XCTAssertEqual(String(repeatScreen), "hoà")

        // 2. `yes` / `yess` / `yesss`, word-final geminates, `away`, and tone-switch English words
        let englishWords = [
            "yes", "yess", "yesss",
            "less", "mess", "boss", "loss", "pass", "miss",
            "kiss", "mass", "guess", "chess", "toss", "moss",
            "fuss", "buff", "cuff", "puff", "tariff", "purr", "swiss",
            "lesson", "lesser", "passing", "missing",
            "away", "awake", "aware", "award", "await",
            "virus", "terms", "turns", "burns", "horns",
            "corns", "barns", "harms", "norms", "worms",
            "surf", "turf", "dwarf"
        ]
        for word in englishWords {
            XCTAssertEqual(simulateTyping(word).output, word, "Failed mid-word English restore: \(word)")
            XCTAssertEqual(simulateTyping(word + " ").output, word + " ", "Failed finalized English restore: \(word)")
        }

        // Intentional single-consonant Telex escapes and abbreviations still work
        let intentionalEscapes: [(String, String)] = [
            ("ass", "as"),
            ("asss", "ass"),
            ("hass", "has"),
            ("gass", "gas"),
            ("buss", "bus"),
            ("hiss", "his"),
            ("thiss", "this"),
            ("for", "for"),
            ("forr", "forr"),
            ("carr", "car"),
            ("herr", "her"),
            ("losse", "lose"),
            ("dessign", "design"),
            ("VARR", "VAR"),
            ("POSS", "POS")
        ]
        for (input, expected) in intentionalEscapes {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed intentional escape: \(input)")
        }

        // 3. Initial-`w` English words vs comprehensive Vietnamese `w` -> `ư` combinations
        let initialWEnglish = [
            "was", "war", "wars", "wax", "won", "woo", "wood", "wow",
            "worm", "worn", "warm", "warn", "ways", "wins", "wing", "wink",
            "with", "word", "work", "world", "wrong", "write"
        ]
        for word in initialWEnglish {
            XCTAssertEqual(simulateTyping(word).output, word, "Failed initial-w English restore: \(word)")
            XCTAssertEqual(simulateTyping(word + " ").output, word + " ", "Failed finalized initial-w English: \(word)")
        }

        let vietnameseWCases: [(String, String)] = [
            ("w", "ư"), ("ws", "ứ"), ("wf", "ừ"), ("wr", "ử"), ("wx", "ữ"), ("wj", "ự"),
            ("uwa", "ưa"), ("uwas", "ứa"), ("uwar", "ửa"), ("uwax", "ữa"), ("uwaj", "ựa"),
            ("own", "ơn"), ("cow", "cơ"), ("how", "hơ"), ("mowis", "mới"),
            ("nhw", "như"), ("nhwng", "nhưng"), ("nhwngx", "những"),
            ("twf", "từ"), ("thwr", "thử"), ("thwongf", "thường"),
            ("chw", "chư"), ("chwx", "chữ"), ("chwa", "chưa"), ("chwong", "chương"),
            ("trwongf", "trường"), ("trwocs", "trước"),
            ("cwar", "cửa"), ("cwus", "cứu"),
            ("mwa", "mưa"), ("mwcs", "mức"), ("mwoif", "mười"), ("mwops", "mướp"),
            ("lwar", "lửa"), ("lwng", "lưng"), ("lwong", "lương"),
            ("nwar", "nửa"), ("nwocs", "nước"),
            ("swax", "sữa"), ("swong", "sương"),
            ("ddwngf", "đừng"), ("ddwcs", "đức"), ("ddwa", "đưa"), ("ddwocj", "được"), ("ddwongf", "đường"),
            ("vwaf", "vừa"), ("vwngx", "vững"),
            ("gwir", "gửi"), ("hwong", "hương"), ("hwou", "hươu"),
            ("rwouj", "rượu"), ("ngwoif", "người"),
            ("giwx", "giữ"), ("giwax", "giữa"), ("giwongf", "giường"),
            ("bwocs", "bước"), ("bwoms", "bướm"),
            ("twois", "tưới"), ("cwois", "cưới")
        ]
        for (input, expected) in vietnameseWCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed Vietnamese w->ư case: \(input)")
            XCTAssertEqual(simulateTyping(input + " ").output, expected + " ", "Failed finalized Vietnamese w->ư case: \(input)")
        }
    }

    func testRound5DieuZeroThrashFreeOrderAndPostSpaceRecovery() {
        // 1. Zero mid-word Backspace thrashing on `ddieeuf` and `dduowcj`
        var dieuEngine = VietInputEngine()
        XCTAssertEqual(dieuEngine.processKey("d"), .passThrough)
        XCTAssertEqual(dieuEngine.processKey("d"), .replace(backspaceCount: 1, text: "đ"))
        XCTAssertEqual(dieuEngine.processKey("i"), .passThrough)
        XCTAssertEqual(dieuEngine.processKey("e"), .passThrough)
        XCTAssertEqual(dieuEngine.currentWord, "đie")
        XCTAssertEqual(dieuEngine.processKey("e"), .replace(backspaceCount: 1, text: "ê"))
        XCTAssertEqual(dieuEngine.currentWord, "điê")
        XCTAssertEqual(dieuEngine.processKey("u"), .passThrough)
        XCTAssertEqual(dieuEngine.processKey("f"), .replace(backspaceCount: 2, text: "ều"))
        XCTAssertEqual(dieuEngine.currentWord, "điều")

        var duocEngine = VietInputEngine()
        XCTAssertEqual(duocEngine.processKey("d"), .passThrough)
        XCTAssertEqual(duocEngine.processKey("d"), .replace(backspaceCount: 1, text: "đ"))
        XCTAssertEqual(duocEngine.processKey("u"), .passThrough)
        XCTAssertEqual(duocEngine.processKey("o"), .passThrough)
        XCTAssertEqual(duocEngine.currentWord, "đuo")
        XCTAssertEqual(duocEngine.processKey("w"), .replace(backspaceCount: 2, text: "ươ"))
        XCTAssertEqual(duocEngine.processKey("c"), .passThrough)
        XCTAssertEqual(duocEngine.processKey("j"), .replace(backspaceCount: 2, text: "ợc"))
        XCTAssertEqual(duocEngine.currentWord, "được")

        // 2. All valid Telex keystroke orders, casing, and VNI orders for `điều`
        let dieuOrders = [
            "ddieeuf", "ddieefu", "ddieuef", "ddieufe", "ddiefue", "ddiefeu", "ddifeeu",
            "dideeuf", "dideefu", "dideuef", "dideufe", "didefeu", "didfeeu",
            "diedeuf", "diedfeu", "dieeufd", "diefeud", "difeeud"
        ]
        for input in dieuOrders {
            XCTAssertEqual(simulateTyping(input).output, "điều", "Failed mid-word điều order: \(input)")
            XCTAssertEqual(simulateTyping(input + " ").output, "điều ", "Failed finalized điều order: \(input)")
        }
        XCTAssertEqual(simulateTyping("Ddieeuf ").output, "Điều ")
        XCTAssertEqual(simulateTyping("Ddiefeu ").output, "Điều ")
        XCTAssertEqual(simulateTyping("DDIEEUF ").output, "ĐIỀU ")

        let vniConfig = EngineConfig(inputMethod: .vni)
        for vniInput in ["d9ie62u ", "d9ieu62 ", "d9ieu26 ", "d9ie2u6 ", "die62u9 "] {
            XCTAssertEqual(simulateTyping(vniInput, config: vniConfig).output, "điều ", "Failed VNI điều: \(vniInput)")
        }

        // 3. Pre-shape tone free-order across other `-iê-`, `-uô-`, `-ươ-`, `-uyê-` words
        let freeOrderPreShapeCases: [(String, String)] = [
            ("nhiefeu ", "nhiều "),
            ("chiefeu ", "chiều "),
            ("kiefeu ", "kiều "),
            ("liefeu ", "liều "),
            ("yefeu ", "yều "),
            ("tieseng ", "tiếng "),
            ("tiefeng ", "tiềng "),
            ("viejet ", "việt "),
            ("cuosoi ", "cuối "),
            ("muosoi ", "muối "),
            ("truofwng ", "trường "),
            ("dduojwc ", "được "),
            ("tuyefen ", "tuyền ")
        ]
        for (input, expected) in freeOrderPreShapeCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed free-order pre-shape case: \(input)")
        }

        // English guards & unfinished intermediate words on Space remain intact
        let preservedCases: [(String, String)] = [
            ("decree ", "decree "),
            ("degree ", "degree "),
            ("dies ", "dies "),
            ("lies ", "lies "),
            ("ties ", "ties "),
            ("yes ", "yes "),
            ("yess ", "yess "),
            ("ddie ", "ddie "),
            ("ddien ", "ddien ")
        ]
        for (input, expected) in preservedCases {
            XCTAssertEqual(simulateTyping(input).output, expected, "Failed preserved English/intermediate case: \(input)")
        }

        // 4. Post-Space Backspace recovery into unfinished `ddieu` / `ddieuf` -> `điều`
        XCTAssertEqual(simulateTyping("ddieu \u{08}ef").output, "điều")
        XCTAssertEqual(simulateTyping("ddieuf \u{08}e").output, "điều")
        XCTAssertEqual(simulateTyping("ddieeuf \u{08}s").output, "điếu")
    }
}
