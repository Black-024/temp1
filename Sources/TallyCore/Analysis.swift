import Foundation

// MARK: - Modelos del análisis

public struct SubmissionPoint { public let key: Int, submittedAt: String, isCompleted: Bool
    public init(key: Int, submittedAt: String, isCompleted: Bool) { self.key = key; self.submittedAt = submittedAt; self.isCompleted = isCompleted } }

public struct Choice: Hashable { public let text: String, origin: String
    public init(_ text: String, _ origin: String) { self.text = text; self.origin = origin } }

public struct AnswerPoint {
    public let key: Int, questionId: String, kind: String, isBlank: Bool, textLen: Int?, choices: [Choice]
    public init(key: Int, questionId: String, kind: String, isBlank: Bool, textLen: Int? = nil, choices: [Choice] = []) {
        self.key = key; self.questionId = questionId; self.kind = kind; self.isBlank = isBlank; self.textLen = textLen; self.choices = choices
    }
}

public struct QuestionInfo {
    public let questionId: String, position: Int, type: String, title: String, options: [String], hasOtherOption: Bool, isDeleted: Bool
    public init(questionId: String, position: Int, type: String, title: String, options: [String] = [], hasOtherOption: Bool = false, isDeleted: Bool = false) {
        self.questionId = questionId; self.position = position; self.type = type; self.title = title
        self.options = options; self.hasOtherOption = hasOtherOption; self.isDeleted = isDeleted
    }
}

/// Filtro ya resuelto: inicio inclusivo, fin exclusivo (ISO UTC).
public struct ResolvedFilter: Equatable { public let kind: String, startIso: String?, endIso: String?, label: String }

public struct Overview: Equatable {
    public let total: Int, completed: Int, partial: Int, firstAt: String?, lastAt: String?, spanDays: Int, perDay: Double?
}
public struct OptionStat: Equatable { public let text: String, count: Int, pct: Double? }
public struct ValueCount: Equatable { public let text: String, count: Int }

public struct QuestionStats {
    public let questionId: String, position: Int, type: String, title: String, kind: String
    public var interpreted: Bool
    public let asked: Int, answered: Int, blank: Int, notAsked: Int, baseNote: String
    public var options: [OptionStat] = []
    public var otherCount = 0
    public var otherValues: [ValueCount] = []
    public var orphanCount = 0
    public var orphanValues: [ValueCount] = []
    public var avgLen: Double?
    public var maxLen: Int?
    public var isDeleted = false
}

/// Fecha y hora local sin zona: se guarda como un `Date` «ingenuo» cuyo valor UTC es la hora de pared local.
public struct LocalDateTime: Comparable, Hashable {
    public let naive: Date
    public init(naive: Date) { self.naive = naive }
    public static func < (a: LocalDateTime, b: LocalDateTime) -> Bool { a.naive < b.naive }
    /// «yyyy-MM-dd HH:mm:ss»
    public var text: String {
        let c = LocalTime.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: naive)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
}

public struct TimeBucket { public let start: LocalDateTime, count: Int }
public struct Timeline { public let bucket: String, points: [TimeBucket], total: Int }

public struct SurveyAnalysis {
    public let formId: String, filter: ResolvedFilter, includeIncomplete: Bool, generatedAt: String
    public let overview: Overview, questions: [QuestionStats], timeline: Timeline, warnings: [String]
}

// MARK: - Aritmética de hora local

enum LocalTime {
    static let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    static func toLocal(_ d: Date, _ tz: TimeZone) -> LocalDateTime {
        LocalDateTime(naive: Date(timeIntervalSince1970: d.timeIntervalSince1970 + Double(tz.secondsFromGMT(for: d))))
    }

    /// Medianoche local del día de [d].
    static func startOfDay(_ n: Date) -> Date { utc.startOfDay(for: n) }

    /// Instante real que corresponde a una hora de pared local.
    static func toInstant(_ l: LocalDateTime, _ tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let c = LocalTime.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: l.naive)
        return cal.date(from: c) ?? l.naive
    }
}

// MARK: - Filtros de tiempo

public enum TimeFilter {
    public static let kinds = ["all", "24h", "7d", "30d", "custom"]
    private static let windows: [String: Double] = ["24h": 24 * 3600, "7d": 7 * 86400, "30d": 30 * 86400]
    private static let labels = ["all": "Todo el período", "24h": "Últimas 24 horas", "7d": "Últimos 7 días", "30d": "Últimos 30 días"]

    /// ISO UTC con ceros en los milisegundos («…:00.000Z»), igual que en las otras versiones.
    public static func toIso(_ d: Date) -> String {
        let c = LocalTime.utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.000Z", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    /// Rango propio: días COMPLETOS en la hora local (extremos incluidos). Las fechas se pasan como (año, mes, día).
    public static func resolve(kind: String, now: Date, tz: TimeZone, start: (Int, Int, Int)? = nil, end: (Int, Int, Int)? = nil) throws -> ResolvedFilter {
        if kind == "all" { return ResolvedFilter(kind: "all", startIso: nil, endIso: nil, label: labels["all"]!) }
        if let w = windows[kind] {
            return ResolvedFilter(kind: kind, startIso: toIso(now.addingTimeInterval(-w)), endIso: toIso(now.addingTimeInterval(1)), label: labels[kind]!)
        }
        if kind == "custom" {
            guard let s = start, let e = end else { throw TallyError(.INTERNAL) }
            func day(_ t: (Int, Int, Int)) -> Date { LocalTime.utc.date(from: DateComponents(year: t.0, month: t.1, day: t.2))! }
            let sd = day(s), ed = day(e)
            if sd > ed { throw TallyError(.INTERNAL) }
            let from = LocalTime.toInstant(LocalDateTime(naive: sd), tz)
            let to = LocalTime.toInstant(LocalDateTime(naive: LocalTime.utc.date(byAdding: .day, value: 1, to: ed)!), tz)
            let label = String(format: "Del %02d/%02d/%04d al %02d/%02d/%04d", s.2, s.1, s.0, e.2, e.1, e.0)
            return ResolvedFilter(kind: "custom", startIso: toIso(from), endIso: toIso(to), label: label)
        }
        throw TallyError(.INTERNAL)
    }
}

// MARK: - Estadísticas puras

/// Reglas: «respondió» = respuesta no vacía; «sin respuesta» = vacía; «no traía la pregunta» aparte;
/// porcentajes sobre quienes respondieron esa pregunta; en selección múltiple, de personas (puede superar 100 %).
public enum Stats {
    private static let baseNotes = [
        "single": "% sobre quienes respondieron esta pregunta",
        "multi": "% de personas que respondieron esta pregunta (puede sumar más de 100 %)",
        "text": "", "raw": "",
    ]
    private static let kindByType = ["MULTIPLE_CHOICE": "single", "CHECKBOXES": "multi", "TEXTAREA": "text"]

    public static func pct(_ count: Int, _ base: Int) -> Double? { base <= 0 ? nil : Double(count) * 100.0 / Double(base) }

    private static func instant(_ iso: String) -> Date { Iso.parse(iso) ?? Date(timeIntervalSince1970: 0) }

    public static func overview(_ subs: [SubmissionPoint], tz: TimeZone) -> Overview {
        if subs.isEmpty { return Overview(total: 0, completed: 0, partial: 0, firstAt: nil, lastAt: nil, spanDays: 0, perDay: nil) }
        let completed = subs.filter { $0.isCompleted }.count
        let first = subs.map { $0.submittedAt }.min()!
        let last = subs.map { $0.submittedAt }.max()!
        let d1 = LocalTime.startOfDay(LocalTime.toLocal(instant(first), tz).naive)
        let d2 = LocalTime.startOfDay(LocalTime.toLocal(instant(last), tz).naive)
        let days = LocalTime.utc.dateComponents([.day], from: d1, to: d2).day ?? 0
        let span = days + 1
        return Overview(total: subs.count, completed: completed, partial: subs.count - completed, firstAt: first, lastAt: last, spanDays: span, perDay: Double(subs.count) / Double(span))
    }

    private static func ranked(_ m: [String: Int]) -> [ValueCount] {
        m.map { ValueCount(text: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text }
    }

    public static func questionStats(_ q: QuestionInfo, answers: [AnswerPoint], totalSubmissions: Int) -> QuestionStats {
        let kind = kindByType[q.type] ?? "raw"
        var rows: [Int: AnswerPoint] = [:]
        for a in answers { rows[a.key] = a }                       // una respuesta por envío y pregunta
        let asked = rows.count
        let answeredRows = rows.values.filter { !$0.isBlank }
        let answered = answeredRows.count
        var base = QuestionStats(questionId: q.questionId, position: q.position, type: q.type, title: q.title, kind: kind, interpreted: false,
                                 asked: asked, answered: answered, blank: asked - answered, notAsked: max(0, totalSubmissions - asked), baseNote: baseNotes[kind]!)
        base.isDeleted = q.isDeleted
        if kind == "single" || kind == "multi" {
            var declared: [String: Int] = [:], other: [String: Int] = [:], orphan: [String: Int] = [:]
            for a in answeredRows {
                var seen = Set<Choice>()
                for c in a.choices {
                    if !seen.insert(c).inserted { continue }       // una persona cuenta una sola vez por opción
                    switch c.origin {
                    case "declared": declared[c.text, default: 0] += 1
                    case "other": other[c.text, default: 0] += 1
                    default: orphan[c.text, default: 0] += 1
                    }
                }
            }
            var options = q.options.map { OptionStat(text: $0, count: declared[$0] ?? 0, pct: pct(declared[$0] ?? 0, answered)) }
            let known = Set(q.options)
            // opciones «declared» que ya no figuran en la pregunta: se muestran, nunca se pierden
            for (k, v) in declared.sorted(by: { $0.key < $1.key }) where !known.contains(k) { options.append(OptionStat(text: k, count: v, pct: pct(v, answered))) }
            base.interpreted = true
            base.options = options
            base.otherCount = other.values.reduce(0, +); base.otherValues = ranked(other)
            base.orphanCount = orphan.values.reduce(0, +); base.orphanValues = ranked(orphan)
            return base
        }
        if kind == "text" {
            let lens = answeredRows.map { $0.textLen ?? 0 }
            base.interpreted = true
            base.avgLen = lens.isEmpty ? nil : Double(lens.reduce(0, +)) / Double(lens.count)
            base.maxLen = lens.max()
        }
        return base
    }

    public static func allQuestionStats(_ questions: [QuestionInfo], answers: [AnswerPoint], totalSubmissions: Int) -> [QuestionStats] {
        let byQ = Dictionary(grouping: answers, by: { $0.questionId })
        return questions.sorted { $0.position != $1.position ? $0.position < $1.position : $0.questionId < $1.questionId }
            .map { questionStats($0, answers: byQ[$0.questionId] ?? [], totalSubmissions: totalSubmissions) }
    }

    // ---------- evolución en el tiempo ----------
    private static func floor(_ dt: LocalDateTime, _ bucket: String) -> LocalDateTime {
        let cal = LocalTime.utc
        switch bucket {
        case "hour": return LocalDateTime(naive: cal.dateInterval(of: .hour, for: dt.naive)!.start)
        case "day": return LocalDateTime(naive: cal.startOfDay(for: dt.naive))
        default:
            var c = cal.dateComponents([.year, .month], from: dt.naive); c.day = 1
            return LocalDateTime(naive: cal.date(from: c)!)
        }
    }

    private static func next(_ dt: LocalDateTime, _ bucket: String) -> LocalDateTime {
        let comp: Calendar.Component = bucket == "hour" ? .hour : (bucket == "day" ? .day : .month)
        return LocalDateTime(naive: LocalTime.utc.date(byAdding: comp, value: 1, to: dt.naive)!)
    }

    /// hour hasta 48 h, day hasta 400 días, month más allá.
    public static func chooseBucket(_ first: LocalDateTime, _ last: LocalDateTime) -> String {
        let span = last.naive.timeIntervalSince(first.naive)
        if span <= 48 * 3600 { return "hour" }
        if span <= 400 * 86400 { return "day" }
        return "month"
    }

    /// Cuenta por intervalo en hora local, rellenando con ceros. [start]/[end] fijan el eje; si faltan, va de la primera a la última.
    public static func timeline(_ subs: [SubmissionPoint], tz: TimeZone, start: Date? = nil, end: Date? = nil) -> Timeline {
        let locs = subs.map { LocalTime.toLocal(instant($0.submittedAt), tz) }
        if locs.isEmpty && (start == nil || end == nil) { return Timeline(bucket: "day", points: [], total: 0) }
        let lo = start.map { LocalTime.toLocal($0, tz) } ?? locs.min()!
        var hi = end.map { LocalTime.toLocal($0, tz) } ?? locs.max()!
        if hi < lo { hi = lo }
        let bucket = chooseBucket(lo, hi)
        var counts: [LocalDateTime: Int] = [:]
        for d in locs { counts[floor(d, bucket), default: 0] += 1 }
        var points: [TimeBucket] = []
        var cur = floor(lo, bucket)
        let last = floor(hi, bucket)
        while cur <= last {
            points.append(TimeBucket(start: cur, count: counts[cur] ?? 0))
            cur = next(cur, bucket)
        }
        return Timeline(bucket: bucket, points: points, total: locs.count)
    }
}
