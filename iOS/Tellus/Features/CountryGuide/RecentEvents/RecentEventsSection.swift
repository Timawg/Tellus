import SwiftUI

struct RecentEventsSection: View {
    let recentEvents: RecentEvents

    /// The latest events, newest first; older ones behind "More events".
    var body: some View {
        let shown = 5
        let events = recentEvents.events
        return Section {
            ForEach(events.prefix(shown)) { event in
                eventRow(event)
            }
            if events.count > shown {
                DisclosureGroup("More events") {
                    ForEach(events.dropFirst(shown).prefix(25)) { event in
                        eventRow(event)
                    }
                }
            }
        } header: {
            Label("Recent events", systemImage: "newspaper")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("From the Wikipedia article “\(recentEvents.articleTitle)”, written by volunteers (CC BY-SA 4.0).")
                if let url = recentEvents.articleURL {
                    Link("Read on Wikipedia", destination: url)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func eventRow(_ event: RecentEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.date, format: .dateTime.day().month(.abbreviated).year())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(event.text)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
