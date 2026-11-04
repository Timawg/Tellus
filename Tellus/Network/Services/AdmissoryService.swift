//
//  AdmissoryService.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-24.
//

import Foundation

protocol AdmissoryServiceProtocol: Service {
    func getAdmissoryStatus(passport: String, destination: String) async throws -> AdmissoryStatus
}

/// Provides visa requirements from the open Passport Index dataset
/// (ilyankou/passport-index-dataset), served over the jsDelivr CDN. The
/// previous API (rough-sun-2523.fly.dev) is no longer available. The dataset is
/// a single CSV covering every passport/destination pair, so we fetch and parse
/// it once and cache the result in memory. `actor` isolation keeps that cache
/// safe from concurrent lookups.
actor AdmissoryService: AdmissoryServiceProtocol {

    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory

    nonisolated let rootURL: String = "https://cdn.jsdelivr.net/gh/ilyankou/passport-index-dataset@master"

    /// Requirement per passport/destination pair, keyed "PASSPORT>DESTINATION".
    private var requirements: [String: String]?

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    enum AdmissoryEndpoint: Endpoint {
        case dataset

        var path: String {
            switch self {
            case .dataset:
                "/passport-index-tidy-iso2.csv"
            }
        }

        var httpMethod: HTTPMethod {
            return .get
        }
    }

    func getAdmissoryStatus(passport: String, destination: String) async throws -> AdmissoryStatus {
        let matrix = try await loadRequirements()
        guard let requirement = matrix["\(passport)>\(destination)"] else {
            throw HTTPError.invalidResponse
        }
        return AdmissoryStatus(passport: passport, destination: destination, requirement: requirement)
    }

    private func loadRequirements() async throws -> [String: String] {
        if let requirements {
            return requirements
        }
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: AdmissoryEndpoint.dataset)
        let data: Data = try await networkService.send(request: request)
        let parsed = Self.parse(csv: data)
        requirements = parsed
        return parsed
    }

    /// Parses the tidy CSV ("Passport,Destination,Requirement") into a lookup map.
    private nonisolated static func parse(csv data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            let passport = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let requirement = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
            result["\(passport)>\(destination)"] = requirement
        }
        return result
    }
}
