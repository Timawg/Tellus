import SwiftUI

@MainActor
@Observable
final class GPSJAMLayerState {
    struct Request: Equatable {
        let isActive: Bool
        let day: Date?
    }

    var selectedDay: Date?
    var selectedCell: GPSJAMCell?
    private(set) var overlay: GPSJAMOverlay?
    private(set) var message: String?
    private var recentDays = GPSJAMService.recentDays()

    var selectableDays: [Date] {
        guard let selectedDay, !recentDays.contains(selectedDay) else { return recentDays }
        return recentDays + [selectedDay]
    }

    func load(_ request: Request, fetch: (Date?) async throws -> GPSJAMOverlay) async {
        guard request.isActive, !Task.isCancelled else { return }
        if let day = request.day, overlay?.day != GPSJAMService.dayLabel(day) {
            overlay = nil
        }
        repeat {
            recentDays = GPSJAMService.recentDays()
            if overlay == nil { message = "Loading GPSJAM…" }
            do {
                let result = try await fetch(request.day)
                guard !Task.isCancelled else { return }
                overlay = result
                message = nil
            } catch {
                guard !Task.isCancelled else { return }
                message = overlay == nil ? "GPSJAM data unavailable" : "Couldn’t refresh GPSJAM"
            }
            guard request.day == nil else { return }
            try? await Task.sleep(for: .seconds(30 * 60))
        } while !Task.isCancelled
    }
}

struct GPSJAMLegend: View {
    let state: GPSJAMLayerState

    var body: some View {
        VStack(spacing: 3) {
            if let message = state.message {
                Text(message)
            }
            if let overlay = state.overlay {
                if overlay.shapes.isEmpty {
                    Text("No elevated reports")
                } else {
                    HStack(spacing: 6) {
                        key("Elevated", level: .elevated)
                        key("High", level: .high)
                    }
                }
                Text("\(overlay.day) UTC")
            }
            Link("GPSJAM", destination: URL(string: "https://gpsjam.org/faq")!)
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
    }

    private func key(_ name: String, level: GPSJAMCell.Level) -> some View {
        Label {
            Text(name)
        } icon: {
            Circle()
                .fill(Color(cgColor: level.color))
                .frame(width: 7, height: 7)
        }
    }
}

struct GPSJAMCellDetails: View {
    let cell: GPSJAMCell
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Observation date", value: "\(cell.day) UTC")
                    LabeledContent("Aircraft sampled", value: cell.total.formatted())
                    LabeledContent("Low accuracy", value: cell.bad.formatted())
                    LabeledContent("Share reporting low accuracy", value: cell.observedShare.formatted(.percent.precision(.fractionLength(1))))
                    LabeledContent("Adjusted share used for shading", value: cell.adjustedShare.formatted(.percent.precision(.fractionLength(1))))
                } footer: {
                    Text("Aircraft report their navigation accuracy via ADS-B. Low accuracy can indicate interference. GPSJAM discounts one low-accuracy aircraft per cell. Tellus shades cells sampled by at least five aircraft.")
                }
                Section {
                    Link("View this day on GPSJAM", destination: URL(string: "https://gpsjam.org/?date=\(cell.day)")!)
                    Link("GPSJAM methodology", destination: URL(string: "https://gpsjam.org/faq")!)
                }
            }
            .navigationTitle("Possible GPS interference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
