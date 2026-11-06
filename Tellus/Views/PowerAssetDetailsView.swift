import SwiftUI

struct PowerAssetDetailsView: View {
    let asset: PowerGridAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Type", value: asset.kind.rawValue)
                    if let operatorName = asset.operatorName {
                        LabeledContent("Operator", value: operatorName)
                    }
                    if let voltage = asset.voltage, voltage > 0 {
                        LabeledContent("Voltage", value: "\(voltage.formatted(.number.precision(.fractionLength(0...2)))) kV")
                    }
                    if let energySource = asset.energySource {
                        LabeledContent("Energy source", value: energySource.replacingOccurrences(of: "_", with: " "))
                    }
                }
                Link("View on OpenStreetMap", destination: asset.sourceURL)
            }
            .navigationTitle(asset.name ?? asset.kind.rawValue)
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
