import SwiftUI

struct NationalityPickerView: View {

    let countries: [Country]
    @Binding var selection: Country?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [Country] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return countries }
        return countries.filter { $0.name?.common?.localizedStandardContains(query) == true }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(matches) { country in
                        Button {
                            selection = country
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                AsyncFlagView(flag: country.flagURL, size: CGSize(width: 36, height: 24))
                                Text(country.name?.common ?? "")
                                Spacer()
                                if country.cca2 == selection?.cca2 {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        // Rows read as a list of names, not as links.
                        .tint(.primary)
                        .accessibilityAddTraits(country.cca2 == selection?.cca2 ? .isSelected : [])
                    }
                } header: {
                    Text("Choose the passport you travel on to see visa requirements for each country.")
                        .textCase(nil)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search countries")
            .navigationTitle("Your passport")
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
