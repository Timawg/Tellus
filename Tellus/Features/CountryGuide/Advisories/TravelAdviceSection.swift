import SwiftUI

struct TravelAdviceSection: View {
    let topic: DestinationGuide.Topic
    let guide: DestinationGuide?
    let isLoading: Bool

    var body: some View {
        if let guide {
            let sections = guide.sections(for: topic)
            if sections.isEmpty {
                ContentUnavailableView("No \(topic.heading.lowercased()) advice",
                                       systemImage: "doc.text.magnifyingglass")
            } else {
                if let introduction = sections.first(where: { $0.title == nil }) {
                    Section(topic.heading) {
                        AdviceBlocks(blocks: introduction.blocks)
                    }
                }
                Section(sections.first?.title == nil ? "Topics" : topic.heading) {
                    ForEach(sections.filter { $0.title != nil }) { section in
                        DisclosureGroup {
                            AdviceBlocks(blocks: section.blocks)
                                .padding(.vertical, 4)
                        } label: {
                            Text(section.title ?? "")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
            }
        } else if isLoading {
            AdviceLoadingRow()
        } else {
            ContentUnavailableView("No travel advice",
                                   systemImage: "doc.text.magnifyingglass",
                                   description: Text("There's no travel advice for this destination."))
        }
    }
}

struct AdviceLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading advice…")
                .foregroundStyle(.secondary)
        }
    }
}

struct AdviceBlocks: View {
    let blocks: [AdviceSection.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(text)
                    }
                    .padding(.leading, 4)
                case .subheading(let text):
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
