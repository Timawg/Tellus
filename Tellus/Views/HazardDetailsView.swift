//
//  HazardDetailsView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import SwiftUI
import CoreLocation

/// A natural hazard tapped on the map: what it is, how strong, when it
/// began and a link to the source's own report.
struct HazardDetailsView: View {

    let hazard: NaturalHazard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    detailRows
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = hazard.url {
                            Link(linkTitle, destination: url)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        Text(attribution)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(hazard.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: hazard.kind.symbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(uiColor: hazard.severity.color)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hazard.name)
                    .font(.title3.weight(.semibold))
                if let place = hazard.place {
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detailRows: some View {
        switch hazard.kind {
        case .earthquake:
            if let magnitude = hazard.magnitude {
                LabeledContent("Magnitude", value: magnitude.formatted(.number.precision(.fractionLength(1))))
            }
            if let depth = hazard.depth {
                LabeledContent("Depth", value: Measurement(value: depth, unit: UnitLength.kilometers)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))))
            }
            if let date = hazard.date {
                LabeledContent("Struck") {
                    Text("\(date, style: .relative) ago")
                }
                LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let level = hazard.alertLevel {
                LabeledContent("Estimated impact") {
                    Text(impactText(level))
                        .foregroundStyle(levelColor(level))
                }
            }
            if hazard.mayCauseTsunami {
                Label("In an ocean region where a tsunami is possible. Follow local warnings.", systemImage: "water.waves")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        case .volcano:
            if let date = hazard.date {
                LabeledContent("Erupting since", value: eruptionStart(date))
            }
            if let explosivity = hazard.explosivity {
                LabeledContent("Largest explosion", value: "VEI \(explosivity) of 8")
            }
            if let level = hazard.alertLevel {
                LabeledContent("GDACS alert") {
                    Text(impactText(level))
                        .foregroundStyle(levelColor(level))
                }
            }
        default:
            if let level = hazard.alertLevel {
                LabeledContent("GDACS alert") {
                    Text(impactText(level))
                        .foregroundStyle(levelColor(level))
                }
            }
            if let summary = hazard.summary {
                LabeledContent(summaryLabel, value: summary)
            }
            if let date = hazard.date {
                LabeledContent("Began", value: date.formatted(date: .abbreviated, time: .omitted))
            }
            if let updated = hazard.updated {
                LabeledContent("Last report", value: updated.formatted(date: .abbreviated, time: .shortened))
            }
        }
        LabeledContent("Location", value: coordinateText(hazard.coordinate))
    }

    // MARK: Text

    private var summaryLabel: String {
        switch hazard.kind {
        case .cyclone: "Wind"
        case .wildfire: "Area"
        default: "Severity"
        }
    }

    private var linkTitle: String {
        switch hazard.source {
        case .usgs: "View on USGS"
        case .gdacs: "View GDACS report"
        case .smithsonian: "View on the Global Volcanism Program"
        }
    }

    private var attribution: String {
        switch hazard.source {
        case .usgs:
            "Earthquake data from the U.S. Geological Survey. Magnitude 4.5 and up from the past week."
        case .gdacs:
            "From GDACS, the Global Disaster Alert and Coordination System of the United Nations and the European Commission. Alerts estimate humanitarian impact."
        case .smithsonian:
            "Ongoing eruptions from the Smithsonian Institution's Global Volcanism Program. Activity varies; check local authorities before visiting."
        }
    }

    private func impactText(_ level: String) -> String {
        switch level.lowercased() {
        case "green": "Green · low"
        case "yellow": "Yellow · moderate"
        case "orange": "Orange · significant"
        case "red": "Red · severe"
        default: level
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "green": .green
        case "yellow": .yellow
        case "orange": .orange
        case "red": .red
        default: .secondary
        }
    }

    /// Eruptions can have been going for decades; show the year for those.
    private func eruptionStart(_ date: Date) -> String {
        if date < Date().addingTimeInterval(-365 * 24 * 60 * 60) {
            return date.formatted(.dateTime.year())
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        let latitude = abs(coordinate.latitude).formatted(.number.precision(.fractionLength(2)))
        let longitude = abs(coordinate.longitude).formatted(.number.precision(.fractionLength(2)))
        return "\(latitude)° \(coordinate.latitude >= 0 ? "N" : "S"), \(longitude)° \(coordinate.longitude >= 0 ? "E" : "W")"
    }
}
