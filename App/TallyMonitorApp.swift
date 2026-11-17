import SwiftUI
import TallyCore

@main
struct TallyMonitorApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Pantalla inicial de la etapa 1: confirma que la app instala y que el núcleo (JSON, fechas, estadísticas) funciona en el aparato.
struct RootView: View {
    @State private var checks: [(String, Bool)] = []

    var body: some View {
        VStack(spacing: 18) {
            Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96)
            Text("Tally Monitor").font(.system(size: 30, weight: .heavy))
            Text("iPhone 1.0 · etapa 1 de la compilación").font(.footnote).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                    HStack { Text(c.1 ? "OK" : "FALLO").bold().foregroundStyle(c.1 ? .green : .red); Text(c.0) }
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.4)))
            Spacer()
            Text("Tally Monitor: iPhone 1.0. Por: Valentín Mangano").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .onAppear { checks = SelfCheck.run() }
    }
}

enum SelfCheck {
    static func run() -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        let text = "{\"z\": 1, \"a\": [1, 2.5, \"á\"]}"
        out.append(("JSON conserva el orden y el formato", (try? Json.parse(text)).map { Json.stringify($0) == text } ?? false))
        let tz = TimeZone(secondsFromGMT: -3 * 3600)!
        let f = try? TimeFilter.resolve(kind: "24h", now: Iso.parse("2026-11-10T15:00:00.000Z")!, tz: tz)
        out.append(("Filtro de 24 horas", f?.startIso == "2026-11-09T15:00:00.000Z"))
        let subs = [SubmissionPoint(key: 1, submittedAt: "2026-02-01T10:00:00.000Z", isCompleted: true),
                    SubmissionPoint(key: 2, submittedAt: "2026-02-03T10:00:00.000Z", isCompleted: false)]
        out.append(("Resumen de envíos", Stats.overview(subs, tz: tz).spanDays == 3))
        out.append(("La clave nunca se imprime", "\(Secret("tly-abcdef123456"))" == "***"))
        return out
    }
}
