//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class StringTest: XCTestCase {
    func test_digitsOnly() {
        XCTAssertEqual("".digitsOnly, "")
        XCTAssertEqual("abc".digitsOnly, "")
        XCTAssertEqual("123".digitsOnly, "123")
        XCTAssertEqual("-1.23".digitsOnly, "123")
        XCTAssertEqual("1x2 3".digitsOnly, "123")
        XCTAssertEqual("١23".digitsOnly, "١23")
        XCTAssertEqual("1️⃣23".digitsOnly, "123")
    }

    func test_asciiDigitsOnly() {
        XCTAssertEqual("".asciiDigitsOnly, "")
        XCTAssertEqual("abc".asciiDigitsOnly, "")
        XCTAssertEqual("123".asciiDigitsOnly, "123")
        XCTAssertEqual("-1.23".asciiDigitsOnly, "123")
        XCTAssertEqual("1x2 3".asciiDigitsOnly, "123")
        XCTAssertEqual("1١23".asciiDigitsOnly, "123")
        XCTAssertEqual("19️⃣23".asciiDigitsOnly, "123")
        XCTAssertEqual("6️⃣123".asciiDigitsOnly, "123")
    }

    func test_isAsciiDigitsOnly() throws {
        XCTAssertTrue("".isAsciiDigitsOnly)
        XCTAssertTrue("1".isAsciiDigitsOnly)
        XCTAssertTrue("1234567890".isAsciiDigitsOnly)
        XCTAssertFalse(" ".isAsciiDigitsOnly)
        XCTAssertFalse("x".isAsciiDigitsOnly)
        XCTAssertFalse("x1".isAsciiDigitsOnly)
        XCTAssertFalse("1x".isAsciiDigitsOnly)
        XCTAssertFalse("1.2".isAsciiDigitsOnly)
        XCTAssertFalse("1️⃣".isAsciiDigitsOnly)
        XCTAssertFalse("١٢٣".isAsciiDigitsOnly)
    }

    func test_caesar() {
        XCTAssertEqual("abc", try! "abc".caesar(shift: 0))
        XCTAssertEqual("abc", try! "abc".caesar(shift: 127))

        XCTAssertEqual("bcd", try! "abc".caesar(shift: 1))
        XCTAssertEqual("bcd", try! "abc".caesar(shift: 128))

        XCTAssertEqual("z{b", try! "yza".caesar(shift: 1))
        XCTAssertEqual("|}d", try! "yza".caesar(shift: 3))
        XCTAssertEqual("ef=g", try! "bc:d".caesar(shift: 3))

        let shifted = try! "abc".caesar(shift: 32)
        let roundTrip = try! shifted.caesar(shift: 127 - 32)
        XCTAssertEqual("abc", roundTrip)
    }

    func test_encodedForSelector() {
        XCTAssertEqual("cnN0", "abc".encodedForSelector)
        XCTAssertEqual("abc", "abc".encodedForSelector!.decodedForSelector)

        XCTAssertNotEqual("abcWithFoo:bar:", "abcWithFoo:bar:".encodedForSelector)
        XCTAssertEqual("abcWithFoo:bar:", "abcWithFoo:bar:".encodedForSelector!.decodedForSelector)

        XCTAssertNotEqual("abcWithFoo:bar:zaz1:", "abcWithFoo:bar:zaz1:".encodedForSelector)
        XCTAssertEqual("abcWithFoo:bar:zaz1:", "abcWithFoo:bar:zaz1:".encodedForSelector!.decodedForSelector)
    }

    func test_directionalAppend() {
        // We used to have a rtlSafeAppend helper, but it didn't behave quite like expected
        // because iOS tries to be smart about the language of the string you're appending to.
        //
        // Sanity check that the iOS methods are doing what we want.

        // Basic tests, "a" + "b" = "ab", etc.
        XCTAssertEqual("a" + "b", "ab")
        XCTAssertEqual("hello" + " " + "world", "hello world")
        XCTAssertEqual("a" + " " + "1" + " " + "b", "a 1 b")

        XCTAssertEqual("ا" + "ب", "اب")
        XCTAssertEqual("مرحبا" + " " + "بالعالم", "مرحبا بالعالم")
        XCTAssertEqual("ا" + " " + "1" + " " + "ب", "ا 1 ب")

        // Test a common usage, similar to `formatPastTimestampRelativeToNow` where we append a time to a date.

        let testTime = "9:41"

        let testStrings: [(day: String, expectedConcatentation: String)] = [
            // LTR Tests
            ("Today", "Today 9:41"), // English
            ("Heute", "Heute 9:41"), // German

            // RTL Tests
            ("اليوم", "اليوم 9:41"), // Arabic
            ("היום", "היום 9:41") // Hebrew
        ]

        for (day, expectedConcatentation) in testStrings {
            XCTAssertEqual(day + " " + testTime, expectedConcatentation)
            XCTAssertEqual((day as NSString).appending(" ").appending(testTime), expectedConcatentation)
            XCTAssertEqual(NSAttributedString(string: day) + " " + testTime, NSAttributedString(string: expectedConcatentation))
        }
    }

    func test_formatDurationLossless() {
        let secondsPerMinute: UInt32 = 60
        let secondsPerHour: UInt32 = secondsPerMinute * 60
        let secondsPerDay: UInt32 = secondsPerHour * 24
        let secondsPerWeek: UInt32 = secondsPerDay * 7
        let secondsPerYear: UInt32 = secondsPerDay * 365

        let format: (UInt32) -> String = String.formatDurationLossless

        XCTAssertEqual(format(0), "0 seconds")
        XCTAssertEqual(format(1), "1 second")
        XCTAssertEqual(format(2), "2 seconds")

        XCTAssertEqual(format(1 * secondsPerMinute - 1), "59 seconds")
        XCTAssertEqual(format(1 * secondsPerMinute), "1 minute")
        XCTAssertEqual(format(1 * secondsPerMinute + 1), "1 minute, 1 second")
        XCTAssertEqual(format(1 * secondsPerMinute + 2), "1 minute, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerMinute - 1), "1 minute, 59 seconds")
        XCTAssertEqual(format(2 * secondsPerMinute), "2 minutes")
        XCTAssertEqual(format(2 * secondsPerMinute + 1), "2 minutes, 1 second")
        XCTAssertEqual(format(2 * secondsPerMinute + 2), "2 minutes, 2 seconds")

        XCTAssertEqual(format(1 * secondsPerHour - 1), "59 minutes, 59 seconds")
        XCTAssertEqual(format(1 * secondsPerHour), "1 hour")
        XCTAssertEqual(format(1 * secondsPerHour + 1), "1 hour, 1 second")
        XCTAssertEqual(format(1 * secondsPerHour + 2), "1 hour, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerHour + 1 * secondsPerMinute + 1), "1 hour, 1 minute, 1 second")
        XCTAssertEqual(format(1 * secondsPerHour + 1 * secondsPerMinute + 2), "1 hour, 1 minute, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerHour + 2 * secondsPerMinute + 1), "1 hour, 2 minutes, 1 second")
        XCTAssertEqual(format(1 * secondsPerHour + 2 * secondsPerMinute + 2), "1 hour, 2 minutes, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerHour - 1), "1 hour, 59 minutes, 59 seconds")
        XCTAssertEqual(format(2 * secondsPerHour), "2 hours")
        XCTAssertEqual(format(2 * secondsPerHour + 1), "2 hours, 1 second")
        XCTAssertEqual(format(2 * secondsPerHour + 2), "2 hours, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerHour + 1 * secondsPerMinute + 1), "2 hours, 1 minute, 1 second")
        XCTAssertEqual(format(2 * secondsPerHour + 1 * secondsPerMinute + 2), "2 hours, 1 minute, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerHour + 2 * secondsPerMinute + 1), "2 hours, 2 minutes, 1 second")
        XCTAssertEqual(format(2 * secondsPerHour + 2 * secondsPerMinute + 2), "2 hours, 2 minutes, 2 seconds")

        XCTAssertEqual(format(1 * secondsPerDay - 1), "23 hours, 59 minutes, 59 seconds")
        XCTAssertEqual(format(1 * secondsPerDay), "1 day")
        XCTAssertEqual(format(1 * secondsPerDay + 1), "1 day, 1 second")
        XCTAssertEqual(format(1 * secondsPerDay + 2), "1 day, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerDay + 1 * secondsPerHour + 1), "1 day, 1 hour, 1 second")
        XCTAssertEqual(format(1 * secondsPerDay + 1 * secondsPerHour + 2), "1 day, 1 hour, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerDay + 2 * secondsPerHour + 1), "1 day, 2 hours, 1 second")
        XCTAssertEqual(format(1 * secondsPerDay + 2 * secondsPerHour + 2), "1 day, 2 hours, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerDay - 1), "1 day, 23 hours, 59 minutes, 59 seconds")
        XCTAssertEqual(format(2 * secondsPerDay), "2 days")
        XCTAssertEqual(format(2 * secondsPerDay + 1), "2 days, 1 second")
        XCTAssertEqual(format(2 * secondsPerDay + 2), "2 days, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerDay + 1 * secondsPerHour + 1), "2 days, 1 hour, 1 second")
        XCTAssertEqual(format(2 * secondsPerDay + 1 * secondsPerHour + 2), "2 days, 1 hour, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerDay + 2 * secondsPerHour + 1), "2 days, 2 hours, 1 second")
        XCTAssertEqual(format(2 * secondsPerDay + 2 * secondsPerHour + 2), "2 days, 2 hours, 2 seconds")

        XCTAssertEqual(format(1 * secondsPerWeek - 1), "6 days, 23 hours, 59 minutes, 59 seconds")
        XCTAssertEqual(format(1 * secondsPerWeek), "1 week")
        XCTAssertEqual(format(1 * secondsPerWeek + 1), "1 week, 1 second")
        XCTAssertEqual(format(1 * secondsPerWeek + 2), "1 week, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerWeek + 1 * secondsPerDay + 1), "1 week, 1 day, 1 second")
        XCTAssertEqual(format(1 * secondsPerWeek + 1 * secondsPerDay + 2), "1 week, 1 day, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerWeek + 2 * secondsPerDay + 1), "1 week, 2 days, 1 second")
        XCTAssertEqual(format(1 * secondsPerWeek + 2 * secondsPerDay + 2), "1 week, 2 days, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerWeek - 1), "1 week, 6 days, 23 hours, 59 minutes, 59 seconds")
        XCTAssertEqual(format(2 * secondsPerWeek), "2 weeks")
        XCTAssertEqual(format(2 * secondsPerWeek + 1), "2 weeks, 1 second")
        XCTAssertEqual(format(2 * secondsPerWeek + 2), "2 weeks, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerWeek + 1 * secondsPerDay + 1), "2 weeks, 1 day, 1 second")
        XCTAssertEqual(format(2 * secondsPerWeek + 1 * secondsPerDay + 2), "2 weeks, 1 day, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerWeek + 2 * secondsPerDay + 1), "2 weeks, 2 days, 1 second")
        XCTAssertEqual(format(2 * secondsPerWeek + 2 * secondsPerDay + 2), "2 weeks, 2 days, 2 seconds")

        XCTAssertEqual(format(1 * secondsPerYear - 1), "52 weeks, 23 hours, 59 minutes, 59 seconds")
        XCTAssertEqual(format(1 * secondsPerYear), "1 year")
        XCTAssertEqual(format(1 * secondsPerYear + 1), "1 year, 1 second")
        XCTAssertEqual(format(1 * secondsPerYear + 2), "1 year, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerYear + 1 * secondsPerWeek + 1), "1 year, 1 week, 1 second")
        XCTAssertEqual(format(1 * secondsPerYear + 1 * secondsPerWeek + 2), "1 year, 1 week, 2 seconds")
        XCTAssertEqual(format(1 * secondsPerYear + 2 * secondsPerWeek + 1), "1 year, 2 weeks, 1 second")
        XCTAssertEqual(format(1 * secondsPerYear + 2 * secondsPerWeek + 2), "1 year, 2 weeks, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerYear - 1), "1 year, 52 weeks, 23 hours, 59 minutes, 59 seconds")
        XCTAssertEqual(format(2 * secondsPerYear), "2 years")
        XCTAssertEqual(format(2 * secondsPerYear + 1), "2 years, 1 second")
        XCTAssertEqual(format(2 * secondsPerYear + 2), "2 years, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerYear + 1 * secondsPerWeek + 1), "2 years, 1 week, 1 second")
        XCTAssertEqual(format(2 * secondsPerYear + 1 * secondsPerWeek + 2), "2 years, 1 week, 2 seconds")
        XCTAssertEqual(format(2 * secondsPerYear + 2 * secondsPerWeek + 1), "2 years, 2 weeks, 1 second")
        XCTAssertEqual(format(2 * secondsPerYear + 2 * secondsPerWeek + 2), "2 years, 2 weeks, 2 seconds")

        let aVeryLongTime = 88 * secondsPerYear + 7 * secondsPerWeek + 6 * secondsPerDay + 5 * secondsPerHour + 4 * secondsPerMinute + 3
        XCTAssertEqual(format(aVeryLongTime), "88 years, 7 weeks, 6 days, 5 hours, 4 minutes, 3 seconds")
    }

    func testIsStructurallyValidE164() {
        let testCases: [(String, Bool)] = [
            // E164 must have leading +.
            ("+5218341639157", true),
            ("5218341639157", false),
            ("+18018108311", true),
            ("18018108311", false),
            // E164 must have exactly 1 leading +.
            ("++18018108311", false),
            // E164 must only contains 0-9 arabic digits.
            ("+123a456", false),
            ("+123\u{0661}456", false), // ARABIC-INDIC DIGIT ONE
            ("+123\u{0031}\u{fe0f}\u{20e3}456", false), // KEYCAP DIGIT 1
            // E164 must have at least 1 digit.
            ("+1", true),
            ("+", false),
            // E164 must have no more than 19 digits.
            ("+1234567890123456789", true),
            ("+12345678901234567890", false),
            // E164 must not start with a zero
            ("+0", false),
            ("+0123", false),
            ("+3210", true)
        ]
        for (inputValue, expectedResult) in testCases {
            XCTAssertEqual(inputValue.isStructurallyValidE164, expectedResult, "\(inputValue)")
        }
    }

    func test_filterAsE164() {
        XCTAssertEqual("", ("" as NSString).filterAsE164())
        XCTAssertEqual("", (" " as NSString).filterAsE164())
        XCTAssertEqual("", ("abc" as NSString).filterAsE164())
        XCTAssertEqual("+123123", ("abc+123+123zz" as NSString).filterAsE164())
        XCTAssertEqual("+123123", (("+123" + "مرحبا بالعالم" + "abc+123zz") as NSString).filterAsE164())
        XCTAssertEqual("+123123", ("abc+123zz+123" as NSString).filterAsE164())
        XCTAssertEqual("+123123", ("abc+123zz+123🇨🇦" as NSString).filterAsE164())
        XCTAssertEqual("", ("🇨🇦" as NSString).filterAsE164())
        XCTAssertEqual("1", ("1🇨🇦" as NSString).filterAsE164())
        XCTAssertEqual("1", ("🇨🇦1" as NSString).filterAsE164())
        XCTAssertEqual("", ("🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦" as NSString).filterAsE164())
        XCTAssertEqual("1", ("1🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦" as NSString).filterAsE164())
        XCTAssertEqual("1", ("🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦🇨🇦1" as NSString).filterAsE164())
        XCTAssertEqual("", ("田" as NSString).filterAsE164())
        XCTAssertEqual("1", ("1田" as NSString).filterAsE164())
        XCTAssertEqual("1", ("田1" as NSString).filterAsE164())
        XCTAssertEqual("", ("田田田田田田田" as NSString).filterAsE164())
        XCTAssertEqual("1", ("1田田田田田田" as NSString).filterAsE164())
        XCTAssertEqual("1", ("田田田田田田田1" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "田中さんにあげて下さい" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "パーティーへ行かないか" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "和製漢語" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "部落格" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "사회과학원 어학연구소" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "찦차를 타고 온 펲시맨과 쑛다리 똠방각하" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "社會科學院語學研究所" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "울란바토르" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "𠜎𠜱𠝹𠱓𠱸𠲖𠳏" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "表ポあA鷗ŒéＢ逍Üßªąñ丂㐀𠀀" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "ヽ༼ຈل͜ຈ༽ﾉ ヽ༼ຈل͜ຈ༽ﾉ" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "(｡◕ ∀ ◕｡)" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "｀ｨ(´∀｀∩" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "__ﾛ(,_,*)" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "・(￣∀￣)・:*:" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "ﾟ･✿ヾ╲(｡◕‿◕｡)╱✿･ﾟ" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + ",。・:*:・゜’( ☻ ω ☻ )。・:*:・゜’" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "(╯°□°）╯︵ ┻━┻)" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "(ﾉಥ益ಥ）ﾉ﻿ ┻━┻" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "┬─┬ノ( º _ ºノ)" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "( ͡° ͜ʖ ͡°)" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "¯\\_(ツ)_/¯" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "😍" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "👩🏽" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "👨‍🦰 👨🏿‍🦰 👨‍🦱 👨🏿‍🦱 🦹🏿‍♂️" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "👾 🙇 💁 🙅 🙆 🙋 🙎 🙍" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "🐵 🙈 🙉 🙊" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "❤️ 💔 💌 💕 💞 💓 💗 💖 💘 💝 💟 💜 💛 💚 💙" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "✋🏿 💪🏿 👐🏿 🙌🏿 👏🏿 🙏🏿" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "👨‍👩‍👦 👨‍👩‍👧‍👦 👨‍👨‍👦 👩‍👩‍👧 👨‍👦 👨‍👧‍👦 👩‍👦 👩‍👧‍👦" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "🚾 🆒 🆓 🆕 🆖 🆗 🆙 🏧" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+1230123456789321", ("+123" + "0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "🇺🇸🇷🇺🇸 🇦🇫🇦🇲🇸" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "🇺🇸🇷🇺🇸🇦🇫🇦🇲" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "🇺🇸🇷🇺🇸🇦" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "１２３" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "١٢٣" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "ثم نفس سقطت وبالتحديد،, جزيرتي باستخدام أن دنو. إذ هنا؟ الستار وتنصيب كان. أهّل ايطاليا، بريطانيا-فرنسا قد أخذ. سليمان، إتفاقية بين ما, يذكر الحدود أي بعد, معاملة بولندا، الإطلاق عل إيو." + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "בְּרֵאשִׁית, בָּרָא אֱלֹהִים, אֵת הַשָּׁמַיִם, וְאֵת הָאָרֶץ" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "הָיְתָהtestالصفحات التّحول" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "﷽" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "ﷺ" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "مُنَاقَشَةُ سُبُلِ اِسْتِخْدَامِ اللُّغَةِ فِي النُّظُمِ الْقَائِمَةِ وَفِيم يَخُصَّ التَّطْبِيقَاتُ الْحاسُوبِيَّةُ،" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+1235321", ("+123" + "الكل في المجمو عة (5)" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "᚛ᚄᚓᚐᚋᚒᚄ ᚑᚄᚂᚑᚏᚅ᚜" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "᚛                 ᚜" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "Ṱ̺̺̕o͞ ̷i̲̬͇̪͙n̝̗͕v̟̜̘̦͟o̶̙̰̠kè͚̮̺̪̹̱̤ ̖t̝͕̳̣̻̪͞h̼͓̲̦̳̘̲e͇̣̰̦̬͎ ̢̼̻̱̘h͚͎͙̜̣̲ͅi̦̲̣̰̤v̻͍e̺̭̳̪̰-m̢iͅn̖̺̞̲̯̰d̵̼̟͙̩̼̘̳ ̞̥̱̳̭r̛̗̘e͙p͠r̼̞̻̭̗e̺̠̣͟s̘͇̳͍̝͉e͉̥̯̞̲͚̬͜ǹ̬͎͎̟̖͇̤t͍̬̤͓̼̭͘ͅi̪̱n͠g̴͉ ͏͉ͅc̬̟h͡a̫̻̯͘o̫̟̖͍̙̝͉s̗̦̲.̨̹͈̣" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "̡͓̞ͅI̗̘̦͝n͇͇͙v̮̫ok̲̫̙͈i̖͙̭̹̠̞n̡̻̮̣̺g̲͈͙̭͙̬͎ ̰t͔̦h̞̲e̢̤ ͍̬̲͖f̴̘͕̣è͖ẹ̥̩l͖͔͚i͓͚̦͠n͖͍̗͓̳̮g͍ ̨o͚̪͡f̘̣̬ ̖̘͖̟͙̮c҉͔̫͖͓͇͖ͅh̵̤̣͚͔á̗̼͕ͅo̼̣̥s̱͈̺̖̦̻͢.̛̖̞̠̫̰" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "̗̺͖̹̯͓Ṯ̤͍̥͇͈h̲́e͏͓̼̗̙̼̣͔ ͇̜̱̠͓͍ͅN͕͠e̗̱z̘̝̜̺͙p̤̺̹͍̯͚e̠̻̠͜r̨̤͍̺̖͔̖̖d̠̟̭̬̝͟i̦͖̩͓͔̤a̠̗̬͉̙n͚͜ ̻̞̰͚ͅh̵͉i̳̞v̢͇ḙ͎͟-҉̭̩̼͔m̤̭̫i͕͇̝̦n̗͙ḍ̟ ̯̲͕͞ǫ̟̯̰̲͙̻̝f ̪̰̰̗̖̭̘͘c̦͍̲̞͍̩̙ḥ͚a̮͎̟̙͜ơ̩̹͎s̤.̝̝ ҉Z̡̖̜͖̰̣͉̜a͖̰͙̬͡l̲̫̳͍̩g̡̟̼̱͚̞̬ͅo̗͜.̟" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "̦H̬̤̗̤͝e͜ ̜̥̝̻͍̟́w̕h̖̯͓o̝͙̖͎̱̮ ҉̺̙̞̟͈W̷̼̭a̺̪͍į͈͕̭͙̯̜t̶̼̮s̘͙͖̕ ̠̫̠B̻͍͙͉̳ͅe̵h̵̬͇̫͙i̹͓̳̳̮͎̫̕n͟d̴̪̜̖ ̰͉̩͇͙̲͞ͅT͖̼͓̪͢h͏͓̮̻e̬̝̟ͅ ̤̹̝W͙̞̝͔͇͝ͅa͏͓͔̹̼̣l̴͔̰̤̟͔ḽ̫.͕" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "Z̮̞̠͙͔ͅḀ̗̞͈̻̗Ḷ͙͎̯̹̞͓G̻O̭̗̮" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "˙ɐnbᴉlɐ ɐuƃɐɯ ǝɹolop ʇǝ ǝɹoqɐl ʇn ʇunpᴉpᴉɔuᴉ ɹodɯǝʇ poɯsnᴉǝ op pǝs 'ʇᴉlǝ ƃuᴉɔsᴉdᴉpɐ ɹnʇǝʇɔǝsuoɔ 'ʇǝɯɐ ʇᴉs ɹolop ɯnsdᴉ ɯǝɹo˥" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+12300321", ("+123" + "00˙Ɩ$-" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "Ｔｈｅ ｑｕｉｃｋ ｂｒｏｗｎ ｆｏｘ ｊｕｍｐｓ ｏｖｅｒ ｔｈｅ ｌａｚｙ ｄｏｇ" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "𝐓𝐡𝐞 𝐪𝐮𝐢𝐜𝐤 𝐛𝐫𝐨𝐰𝐧 𝐟𝐨𝐱 𝐣𝐮𝐦𝐩𝐬 𝐨𝐯𝐞𝐫 𝐭𝐡𝐞 𝐥𝐚𝐳𝐲 𝐝𝐨𝐠" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "𝕿𝖍𝖊 𝖖𝖚𝖎𝖈𝖐 𝖇𝖗𝖔𝖜𝖓 𝖋𝖔𝖝 𝖏𝖚𝖒𝖕𝖘 𝖔𝖛𝖊𝖗 𝖙𝖍𝖊 𝖑𝖆𝖟𝖞 𝖉𝖔𝖌" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "𝑻𝒉𝒆 𝒒𝒖𝒊𝒄𝒌 𝒃𝒓𝒐𝒘𝒏 𝒇𝒐𝒙 𝒋𝒖𝒎𝒑𝒔 𝒐𝒗𝒆𝒓 𝒕𝒉𝒆 𝒍𝒂𝒛𝒚 𝒅𝒐𝒈" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "𝓣𝓱𝓮 𝓺𝓾𝓲𝓬𝓴 𝓫𝓻𝓸𝔀𝓷 𝓯𝓸𝔁 𝓳𝓾𝓶𝓹𝓼 𝓸𝓿𝓮𝓻 𝓽𝓱𝓮 𝓵𝓪𝔃𝔂 𝓭𝓸𝓰" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "𝕋𝕙𝕖 𝕢𝕦𝕚𝕔𝕜 𝕓𝕣𝕠𝕨𝕟 𝕗𝕠𝕩 𝕛𝕦𝕞𝕡𝕤 𝕠𝕧𝕖𝕣 𝕥𝕙𝕖 𝕝𝕒𝕫𝕪 𝕕𝕠𝕘" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "𝚃𝚑𝚎 𝚚𝚞𝚒𝚌𝚔 𝚋𝚛𝚘𝚠𝚗 𝚏𝚘𝚡 𝚓𝚞𝚖𝚙𝚜 𝚘𝚟𝚎𝚛 𝚝𝚑𝚎 𝚕𝚊𝚣𝚢 𝚍𝚘𝚐" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "⒯⒣⒠ ⒬⒰⒤⒞⒦ ⒝⒭⒪⒲⒩ ⒡⒪⒳ ⒥⒰⒨⒫⒮ ⒪⒱⒠⒭ ⒯⒣⒠ ⒧⒜⒵⒴ ⒟⒪⒢" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "Powerلُلُصّبُلُلصّبُررً ॣ ॣh ॣ ॣ冗" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+1230321", ("+123" + "🏳0🌈️" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "జ్ఞ‌ా" + "321+" as NSString).filterAsE164())
        XCTAssertEqual("+123321", ("+123" + "گچپژ" + "321+" as NSString).filterAsE164())
    }
}
