import SwiftUI

struct TravelAdviceSection: View {
    let topic: DestinationGuide.Topic
    let guide: DestinationGuide?
    let advisoryStatus: AdvisoryStatus?
    let isLoading: Bool
    let loadFailed: Bool

    var body: some View {
        if let guide {
            if topic == .entry {
                if !guide.advisories.isEmpty {
                    AdviceTopics(sections: guide.advisories) {
                        advisoryHeading
                    }
                } else if let summary = advisoryStatus?.data.eng.advisoryText, !summary.isEmpty {
                    Section {
                        Text(summary)
                    } header: {
                        advisoryHeading
                    }
                }
            }
            let sections = guide.sections(for: topic)
            if sections.isEmpty {
                ContentUnavailableView("No \(topic.heading.lowercased()) advice",
                                       systemImage: "doc.text.magnifyingglass")
            } else {
                AdviceTopics(sections: sections) {
                    Text(topic.heading)
                }
            }
        } else if isLoading {
            AdviceLoadingRow()
        } else {
            ContentUnavailableView(loadFailed ? "Couldn’t load travel advice" : "No travel advice",
                                   systemImage: "doc.text.magnifyingglass")
            if topic == .entry {
                Section {
                    GuideSourceLink("Browse Canadian travel advisories", destination: Self.advisoriesURL)
                }
            }
        }
    }

    private var advisoryHeading: some View {
        HStack(spacing: 8) {
            if let colors = advisoryStatus?.colors, !colors.isEmpty {
                CircularStatusView(colors: colors)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text("Travel advisory")
        }
    }

    private static let advisoriesURL = URL(string: "https://travel.gc.ca/travelling/advisories")!
}

private struct AdviceTopics<Heading: View>: View {
    let sections: [AdviceSection]
    @ViewBuilder let heading: Heading

    var body: some View {
        let introduction = sections.first(where: { $0.title == nil })
        let topics = sections.filter { $0.title != nil }
        if let introduction {
            Section {
                AdviceBlocks(blocks: introduction.blocks)
            } header: {
                heading
            }
        }
        if !topics.isEmpty {
            Section {
                ForEach(topics) { section in
                    DisclosureGroup {
                        AdviceBlocks(blocks: section.blocks)
                            .padding(.vertical, 4)
                    } label: {
                        Text(section.title ?? "")
                            .font(.body.weight(.semibold))
                    }
                }
            } header: {
                if introduction == nil {
                    heading
                } else {
                    Text("Topics")
                }
            }
        }
    }
}

struct GuideAdviceSource: View {
    let guide: DestinationGuide

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Government of Canada advice, adapted for travellers.")
                    .foregroundStyle(.secondary)
                if !guide.updated.isEmpty {
                    Text("Updated \(guide.updated)")
                        .foregroundStyle(.secondary)
                }
                if let url = guide.adviceURL {
                    GuideSourceLink("Full advisory on travel.gc.ca", destination: url)
                }
                GuideSourceLink("Open Government Licence – Canada", destination: Self.licenseURL)
            }
            .font(.footnote)
            .multilineTextAlignment(.leading)
        }
    }

    private static let licenseURL = URL(string: "https://open.canada.ca/en/open-government-licence-canada")!
}

struct GuideSourceLink: View {
    let title: LocalizedStringKey
    let destination: URL

    init(_ title: LocalizedStringKey, destination: URL) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            Text(title)
                .underline()
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.blue)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.borderless)
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
                    Text(underliningLinks(in: text))
                case .bullet(let text, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(depth.isMultiple(of: 2) ? "•" : "◦")
                            .accessibilityHidden(true)
                        Text(underliningLinks(in: text))
                    }
                    .padding(.leading, 4 + 12 * CGFloat(depth))
                case .subheading(let text):
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                }
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func underliningLinks(in text: AttributedString) -> AttributedString {
        var styled = text
        for run in text.runs where run.link != nil {
            styled[run.range].underlineStyle = .single
        }
        return styled
    }
}

#Preview("Travel advisory topics") {
    let html = """
        <h3>Countrywide guidance</h3><p>Check local conditions before travelling.</p>
        <h3>Northern region – Avoid non-essential travel</h3>
        <ul><li>Northern province, excluding:<ul><li>the airport</li></ul></li></ul>
        <p><a href="/travelling/advisories">Official guidance</a></p>
        """
    List {
        AdviceTopics(sections: AdviceSection.sections(fromHTML: html)) {
            Text("Travel advisory")
        }
    }
    .preferredColorScheme(.dark)
}
