//
//  CableDetailsView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import SwiftUI

/// An undersea cable tapped on the map: its length, owners, when it entered
/// service and where it comes ashore.
struct CableDetailsView: View {

    let cable: SubmarineCable
    /// Nil while loading.
    let details: CableDetails?

    @Environment(\.dismiss) private var dismiss

    /// Landing points grouped by country, countries sorted by name.
    private var landingPointsByCountry: [(country: String, points: [CableDetails.LandingPoint])] {
        let grouped = Dictionary(grouping: details?.landingPoints ?? []) { $0.country ?? "Other" }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Capsule()
                            .fill(Color(uiColor: UIColor(hex: cable.colorHex) ?? .systemTeal))
                            .frame(width: 28, height: 6)
                        Text(cable.name)
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                    if let details {
                        if let length = details.length {
                            LabeledContent("Length", value: length)
                        }
                        if let year = details.rfsYear {
                            LabeledContent(details.isPlanned == true ? "Planned for" : "In service since", value: String(year))
                        }
                        if !details.landingPoints.isEmpty {
                            LabeledContent("Landing points", value: "\(details.landingPoints.count) in \(landingPointsByCountry.count) \(landingPointsByCountry.count == 1 ? "country" : "countries")")
                        }
                        if let owners = details.owners, !owners.isEmpty {
                            LabeledContent("Owners") {
                                Text(owners)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        if let suppliers = details.suppliers, !suppliers.isEmpty {
                            LabeledContent("Built by", value: suppliers)
                        }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading details…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if details != nil, !landingPointsByCountry.isEmpty {
                    Section("Comes ashore in") {
                        ForEach(landingPointsByCountry, id: \.country) { group in
                            DisclosureGroup {
                                ForEach(group.points) { point in
                                    Text(point.name)
                                        .font(.subheadline)
                                }
                            } label: {
                                LabeledContent(group.country, value: "\(group.points.count)")
                            }
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = details?.mapURL {
                            Link("View on Submarine Cable Map", destination: url)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        if let website = details?.url.flatMap(URL.init(string:)) {
                            Link("Cable website", destination: website)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        Text("Cable data © TeleGeography, submarinecablemap.com.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Undersea cable")
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
}
