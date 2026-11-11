import SwiftUI

@MainActor
@Observable
final class AuroraLayerState {
    private(set) var overlay: AuroraOverlay?
    private(set) var refreshFailed = false

    func refreshWhileActive(fetch: () async throws -> AuroraOverlay) async {
        while !Task.isCancelled {
            do {
                let forecast = try await fetch()
                guard !Task.isCancelled else { return }
                overlay = forecast
                refreshFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                refreshFailed = true
            }
            try? await Task.sleep(for: .seconds(5 * 60))
        }
    }
}

struct AuroraLegend: View {
    let state: AuroraLayerState

    var body: some View {
        VStack(spacing: 3) {
            if let overlay = state.overlay {
                if overlay.bands.isEmpty {
                    Text("No aurora forecast in map coverage")
                } else {
                    HStack(spacing: 4) {
                        Text("Fainter")
                        HStack(spacing: 1) {
                            ForEach(AuroraOverlay.Band.allCases, id: \.self) { band in
                                Color(cgColor: band.color)
                            }
                        }
                        .frame(width: 36, height: 6)
                        .accessibilityHidden(true)
                        Text("Stronger")
                    }
                    .accessibilityLabel("Forecast intensity, fainter to stronger")
                }
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 3) {
                        Text(overlay.isOlder(at: context.date) ? "Older aurora forecast" : "Aurora forecast valid")
                        Text("\(overlay.validAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: .gmt)) UTC")
                    }
                }
                if state.refreshFailed { Text("Couldn’t refresh aurora") }
            } else {
                Text(state.refreshFailed ? "Aurora forecast unavailable" : "Loading aurora forecast…")
            }
            Link("NOAA SWPC", destination: URL(string: "https://www.spaceweather.gov/products/aurora-30-minute-forecast")!)
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
    }
}
