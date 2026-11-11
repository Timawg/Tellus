//
//  InternetOutages.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import Foundation

/// A period when a country's internet connectivity dropped, seen by at least
/// two of IODA's independent signals at the same time.
struct InternetOutage: Equatable, Identifiable {
    let start: Date
    let end: Date
    /// Still under way when the data was fetched.
    let isOngoing: Bool
    /// Signals that saw it, e.g. "Routing (BGP)" and "Active probing".
    let signals: [String]

    var id: Date { start }
}

/// IODA (Internet Outage Detection and Analysis, Georgia Tech) outage events.
struct IODAEventList: Decodable {

    struct Event: Decodable {
        let start: TimeInterval
        let duration: TimeInterval
        let datasource: String
    }

    let data: [Event]

    private static let signalNames = [
        "bgp": "Routing (BGP)",
        "ping-slash24": "Active probing",
        "merit-nt": "Network telescope",
        "gtr": "Google traffic",
    ]

    /// IODA flags many short blips from a single signal, which are usually
    /// measurement noise. Only periods where two or more independent signals
    /// overlap are kept, newest first.
    func corroboratedOutages(until: Date) -> [InternetOutage] {
        let events = data.sorted { $0.start < $1.start }
        var clusters: [(start: TimeInterval, end: TimeInterval, sources: Set<String>)] = []
        for event in events {
            let end = event.start + event.duration
            if let last = clusters.last, event.start < last.end {
                clusters[clusters.count - 1].end = max(last.end, end)
                clusters[clusters.count - 1].sources.insert(event.datasource)
            } else {
                clusters.append((event.start, end, [event.datasource]))
            }
        }
        let ongoingCutoff = until.timeIntervalSince1970 - 30 * 60
        return clusters
            .filter { $0.sources.count >= 2 }
            .map { cluster in
                InternetOutage(
                    start: Date(timeIntervalSince1970: cluster.start),
                    end: Date(timeIntervalSince1970: cluster.end),
                    isOngoing: cluster.end >= ongoingCutoff,
                    signals: cluster.sources.map { Self.signalNames[$0] ?? $0 }.sorted()
                )
            }
            .sorted { $0.start > $1.start }
    }
}
