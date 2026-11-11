//
//  TravelStatus.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-05.
//

import SwiftUI

/// One of the four things summed up by the dots on the map card's guide
/// button, and shown in full at the top of the guide tab it belongs to.
struct TravelStatus: Identifiable {

    enum Kind: Int {
        case advisory, visa, health, disasters

        /// The guide tab that explains it.
        var topic: DestinationGuide.Topic {
            switch self {
            case .advisory, .visa: .entry
            case .health: .health
            case .disasters: .climate
            }
        }
    }

    let kind: Kind
    let colors: [Color]
    let title: String
    let value: String

    var id: Kind { kind }

    /// How long a WHO report counts as a current outbreak, and how long as a
    /// recent one.
    private static let currentOutbreakAge: TimeInterval = 30 * 24 * 60 * 60
    private static let recentOutbreakAge: TimeInterval = 180 * 24 * 60 * 60

    static func advisory(_ status: AdvisoryStatus?) -> TravelStatus? {
        guard let status, !status.colors.isEmpty else { return nil }
        return TravelStatus(kind: .advisory, colors: status.colors, title: "Travel advisory", value: status.data.eng.advisoryText)
    }

    static func visa(_ status: AdmissoryStatus?, passport: Country?) -> TravelStatus? {
        guard let status, !status.colors.isEmpty else { return nil }
        var value = status.category.capitalized
        if let days = Int(status.dur), days > 0 {
            value += " · up to \(days) days"
        }
        let title = passport?.name?.common.map { "Visa · \($0) passport" } ?? "Visa"
        return TravelStatus(kind: .visa, colors: status.colors, title: title, value: value)
    }

    /// From WHO's outbreak reports for the country: orange for one in the
    /// last 30 days, blue for one in the last six months.
    static func health(_ reports: [OutbreakReport], now: Date = Date()) -> TravelStatus {
        let title = "Disease outbreaks"
        guard let latest = reports.max(by: { $0.published < $1.published }) else {
            return TravelStatus(kind: .health, colors: .secure, title: title, value: "No WHO outbreak reports")
        }
        let age = now.timeIntervalSince(latest.published)
        let date = latest.published.formatted(.dateTime.day().month(.abbreviated))
        if age <= currentOutbreakAge {
            return TravelStatus(kind: .health, colors: .caution, title: title, value: "\(latest.disease), reported \(date)")
        }
        if age <= recentOutbreakAge {
            return TravelStatus(kind: .health, colors: .semisecure, title: title, value: "\(latest.disease), reported \(date)")
        }
        return TravelStatus(kind: .health, colors: .secure, title: title, value: "No WHO reports in the last six months")
    }

    /// From GDACS alerts for the country: red or orange by the worst urgent
    /// alert, blue when only a drought is listed.
    static func disasters(_ alerts: [DisasterAlert]) -> TravelStatus {
        let title = "Natural disasters"
        let urgent = alerts.filter(\.isUrgent)
        if let red = urgent.first(where: { $0.level == .red }) {
            return TravelStatus(kind: .disasters, colors: .danger, title: title, value: "Red alert: \(red.name)")
        }
        if let orange = urgent.first {
            return TravelStatus(kind: .disasters, colors: .caution, title: title, value: "Orange alert: \(orange.name)")
        }
        if let drought = alerts.first {
            return TravelStatus(kind: .disasters, colors: .semisecure, title: title, value: drought.name)
        }
        return TravelStatus(kind: .disasters, colors: .secure, title: title, value: "No active alerts")
    }
}

/// A status as a row: its colour, what it's about and what it says.
struct TravelStatusRow: View {
    let status: TravelStatus

    var body: some View {
        HStack(spacing: 12) {
            CircularStatusView(colors: status.colors)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(status.value)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
