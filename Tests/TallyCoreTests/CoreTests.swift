import XCTest
@testable import TallyCore

final class CoreTests: XCTestCase {
    func testJsonStringifyMatchesPython() throws {
        var o = JObject()
        o["b"] = .int(1); o["a"] = .array([.string("x\"y"), .null, .bool(true), .double(2.0), .double(0.5)])
        o["ñ"] = .string("á\u{01}")
        XCTAssertEqual(Json.stringify(.object(o)), "{\"b\": 1, \"a\": [\"x\\\"y\", null, true, 2.0, 0.5], \"ñ\": \"á\\u0001\"}")
    }

    func testJsonRoundTripKeepsOrder() throws {
        let text = "{\"z\": 1, \"a\": {\"k\": [1, 2.5, \"\\u00e1\\ud83d\\ude00\"]}, \"m\": null}"
        let v = try Json.parse(text)
        XCTAssertEqual(v["a"]?["k"]?.arrayValue?.count, 3)
        XCTAssertEqual(v["a"]?["k"]?.arrayValue?[2].stringValue, "á😀")
        XCTAssertEqual(Json.stringify(v), "{\"z\": 1, \"a\": {\"k\": [1, 2.5, \"á😀\"]}, \"m\": null}")
    }

    func testJsonRejectsGarbage() {
        XCTAssertThrowsError(try Json.parse("{\"a\": 1} x"))
        XCTAssertThrowsError(try Json.parse("{\"a\": "))
    }

    func testSecretNeverPrints() {
        let s = Secret("tly-abcdef123456")
        XCTAssertEqual("\(s)", "***")
        XCTAssertTrue(s.hasTallyKeyShape())
        XCTAssertFalse(Secret("hola").hasTallyKeyShape())
    }

    func testRedactor() {
        XCTAssertEqual(Redactor.redact("clave tly-abcdef123456 y Bearer abc.def-123456"), "clave tly-*** y Bearer ***")
    }

    func testIds() {
        XCTAssertNoThrow(try Ids.check("wMeX1d"))
        XCTAssertThrowsError(try Ids.check("../x"))
        XCTAssertThrowsError(try Ids.check(""))
    }

    func testIsoFormat() {
        XCTAssertEqual(Iso.format(millis: 0), "1970-01-01T00:00:00.000Z")
        XCTAssertNotNil(Iso.parse("2026-02-03T10:00:00.000Z"))
        XCTAssertNotNil(Iso.parse("2026-02-03T10:00:00Z"))
    }
}

final class AnalysisTests: XCTestCase {
    let tz = TimeZone(secondsFromGMT: -3 * 3600)!

    func testTimeFilterGolden() throws {
        let url = Bundle.module.url(forResource: "expected_timefilter", withExtension: "json", subdirectory: "Golden")!
        let exp = try Json.parseObject(String(contentsOf: url, encoding: .utf8))
        let now = Iso.parse(exp["now"]!.stringValue!)!
        for c in exp["cases"]!.arrayValue! {
            let kind = c["kind"]!.stringValue!
            var start: (Int, Int, Int)? = nil, end: (Int, Int, Int)? = nil
            if kind == "custom" {
                func ymd(_ s: String) -> (Int, Int, Int) { let p = s.split(separator: "-").map { Int($0)! }; return (p[0], p[1], p[2]) }
                start = ymd(c["start"]!.stringValue!); end = ymd(c["end"]!.stringValue!)
            }
            let r = try TimeFilter.resolve(kind: kind, now: now, tz: tz, start: start, end: end)
            let e = c["result"]!
            XCTAssertEqual(r.startIso, e["start_iso"]?.stringValue, kind)
            XCTAssertEqual(r.endIso, e["end_iso"]?.stringValue, kind)
            XCTAssertEqual(r.label, e["label"]?.stringValue, kind)
        }
    }

    func testOverviewAndQuestionStats() {
        let subs = [SubmissionPoint(key: 1, submittedAt: "2026-02-01T10:00:00.000Z", isCompleted: true),
                    SubmissionPoint(key: 2, submittedAt: "2026-02-02T10:00:00.000Z", isCompleted: true),
                    SubmissionPoint(key: 3, submittedAt: "2026-02-03T10:00:00.000Z", isCompleted: false)]
        let o = Stats.overview(subs, tz: tz)
        XCTAssertEqual(o.total, 3); XCTAssertEqual(o.completed, 2); XCTAssertEqual(o.partial, 1)
        XCTAssertEqual(o.spanDays, 3); XCTAssertEqual(o.perDay ?? 0, 1.0, accuracy: 1e-9)

        let q = QuestionInfo(questionId: "q1", position: 0, type: "MULTIPLE_CHOICE", title: "Color", options: ["Azul", "Rojo"], hasOtherOption: true)
        let answers = [AnswerPoint(key: 1, questionId: "q1", kind: "single", isBlank: false, choices: [Choice("Azul", "declared")]),
                       AnswerPoint(key: 2, questionId: "q1", kind: "single", isBlank: false, choices: [Choice("Rojo", "declared")]),
                       AnswerPoint(key: 3, questionId: "q1", kind: "single", isBlank: false, choices: [Choice("Verde", "other")])]
        let s = Stats.questionStats(q, answers: answers, totalSubmissions: 3)
        XCTAssertEqual(s.answered, 3)
        XCTAssertEqual(s.options.map { $0.count }, [1, 1])
        XCTAssertEqual(s.options[0].pct ?? 0, 33.333333333333336, accuracy: 1e-9)
        XCTAssertEqual(s.otherCount, 1)
        XCTAssertEqual(s.otherValues, [ValueCount(text: "Verde", count: 1)])
    }

    func testTimelineDaysFillZeros() {
        let subs = [SubmissionPoint(key: 1, submittedAt: "2026-02-01T10:00:00.000Z", isCompleted: true),
                    SubmissionPoint(key: 2, submittedAt: "2026-02-03T10:00:00.000Z", isCompleted: true)]
        let t = Stats.timeline(subs, tz: tz)
        XCTAssertEqual(t.bucket, "day")
        XCTAssertEqual(t.points.map { $0.count }, [1, 0, 1])
        XCTAssertEqual(t.points.first?.start.text, "2026-02-01 00:00:00")
    }
}
