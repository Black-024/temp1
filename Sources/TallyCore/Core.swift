import Foundation

// MARK: - Errores tipados

public enum ErrorCode: String {
    case INVALID_KEY_FORMAT, KEY_REJECTED, FORBIDDEN, NETWORK, TIMEOUT, RATE_LIMITED, SERVER_ERROR, BAD_RESPONSE
    case RESPONSE_TOO_LARGE, NOT_FOUND, PROTECTION_UNAVAILABLE, CREDENTIAL_UNREADABLE, ACCOUNT_MISMATCH
    case DATABASE_TOO_NEW, MIGRATION_FAILED, BACKUP_FAILED, RESTORE_FAILED, SYNC_CANCELLED, EXPORT_FAILED
    case EXPORT_CANCELLED, INVALID_ID, NOT_FOUND_LOCAL, ALREADY_EXISTS, INTERNAL
}

/// Nunca incluye la clave, el cuerpo de una respuesta de la API ni datos de encuestas.
public struct TallyError: Error {
    public let code: ErrorCode
    public let status: Int?
    public let retryAfterSeconds: Int?
    public init(_ code: ErrorCode, status: Int? = nil, retryAfterSeconds: Int? = nil) {
        self.code = code; self.status = status; self.retryAfterSeconds = retryAfterSeconds
    }
}

/// Un identificador de Tally debe ser corto y alfanumérico antes de armar una ruta con él.
public enum Ids {
    @discardableResult
    public static func check(_ id: String) throws -> String {
        let ok = !id.isEmpty && id.utf8.count <= 64 && id.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) || $0 == "_" || $0 == "-"
        }
        if !ok { throw TallyError(.INVALID_ID) }
        return id
    }
}

// MARK: - Fechas

public protocol Clock { func nowMillis() -> Int64 }
public extension Clock { func nowIso() -> String { Iso.format(millis: nowMillis()) } }
public struct SystemClock: Clock {
    public init() {}
    public func nowMillis() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
}

/// ISO-8601 UTC con milisegundos («2026-11-10T12:00:00.000Z»), el formato de Tally.
public enum Iso {
    private static var utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    public static func format(millis: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let ms = Int(((millis % 1000) + 1000) % 1000)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, ms)
    }

    public static func format(_ d: Date) -> String { format(millis: Int64((d.timeIntervalSince1970 * 1000).rounded(.down))) }

    public static func parse(_ text: String) -> Date? {
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: text) { return d }
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
        return b.date(from: text)
    }
}

// MARK: - Secreto y redactor

/// Texto secreto (la API Key). Nunca se muestra: `description` devuelve «***».
public struct Secret: CustomStringConvertible, CustomDebugStringConvertible, Equatable {
    private let value: String
    public init(_ value: String) { self.value = value }
    public func reveal() -> String { value }
    public var description: String { "***" }
    public var debugDescription: String { "***" }
    public func hasTallyKeyShape() -> Bool {
        guard value.utf8.count <= 200, value.hasPrefix("tly-") else { return false }
        let rest = value.unicodeScalars.dropFirst(4)
        return rest.count >= 4 && rest.allSatisfy { $0.value >= 0x21 && $0.value <= 0x7e }
    }
}

/// Oculta cualquier clave de Tally («tly-…») y cabeceras «Bearer …» antes de registrar un texto.
public enum Redactor {
    private static let key = try! NSRegularExpression(pattern: "tly-[A-Za-z0-9_\\-]{6,}")
    private static let bearer = try! NSRegularExpression(pattern: "bearer\\s+[A-Za-z0-9._\\-]{6,}", options: [.caseInsensitive])
    public static func redact(_ text: String) -> String {
        var s = text
        s = key.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "tly-***")
        s = bearer.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "Bearer ***")
        return s
    }
}

// MARK: - Modelos de filas

public struct FormRow: Equatable {
    public var formId: String, name: String, status: String, isClosed: Bool, workspaceId: String?
    public var reportedSubmissions: Int?, createdAt: String?, updatedAt: String?
    public init(formId: String, name: String, status: String, isClosed: Bool, workspaceId: String?, reportedSubmissions: Int?, createdAt: String?, updatedAt: String?) {
        self.formId = formId; self.name = name; self.status = status; self.isClosed = isClosed; self.workspaceId = workspaceId
        self.reportedSubmissions = reportedSubmissions; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct QuestionRow: Equatable {
    public var questionId: String, position: Int, type: String, title: String, reportedResponses: Int?
    public var groupUuid: String?, hasOtherOption: Bool, isDeleted: Bool, options: [String]
    public init(questionId: String, position: Int, type: String, title: String, reportedResponses: Int?, groupUuid: String?, hasOtherOption: Bool, isDeleted: Bool, options: [String] = []) {
        self.questionId = questionId; self.position = position; self.type = type; self.title = title; self.reportedResponses = reportedResponses
        self.groupUuid = groupUuid; self.hasOtherOption = hasOtherOption; self.isDeleted = isDeleted; self.options = options
    }
}

/// origin: declared (está en las opciones) | other (texto de «Otro») | unmatched (no coincide con nada).
public struct ChoiceRow: Equatable {
    public var optionText: String, origin: String
    public init(optionText: String, origin: String) { self.optionText = optionText; self.origin = origin }
}

/// kind: text | single | multi | raw.
public struct AnswerRow: Equatable {
    public var questionId: String, kind: String, textValue: String?, isBlank: Bool, rawJson: String, choices: [ChoiceRow]
    public init(questionId: String, kind: String, textValue: String?, isBlank: Bool, rawJson: String, choices: [ChoiceRow] = []) {
        self.questionId = questionId; self.kind = kind; self.textValue = textValue; self.isBlank = isBlank; self.rawJson = rawJson; self.choices = choices
    }
}

public struct SubmissionRow: Equatable {
    public var submissionId: String, formId: String, submittedAt: String, isCompleted: Bool
    public var createdAt: String?, updatedAt: String?, answers: [AnswerRow]
    public init(submissionId: String, formId: String, submittedAt: String, isCompleted: Bool, createdAt: String?, updatedAt: String?, answers: [AnswerRow] = []) {
        self.submissionId = submissionId; self.formId = formId; self.submittedAt = submittedAt; self.isCompleted = isCompleted
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.answers = answers
    }
}
