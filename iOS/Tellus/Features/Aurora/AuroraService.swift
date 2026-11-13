import Foundation

actor AuroraService: Service {
    nonisolated let rootURL = "https://services.swpc.noaa.gov"
    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    func getForecast() async throws -> AuroraOverlay {
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: LatestForecast())
        let data: Data = try await networkService.send(request: request)
        try Task.checkCancellation()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let grid = try decoder.decode(ForecastGrid.self, from: data)
        return try AuroraOverlay(validAt: grid.validAt, coordinates: grid.coordinates)
    }

    private struct LatestForecast: Endpoint {
        let path = "/json/ovation_aurora_latest.json"
        let httpMethod: HTTPMethod = .get
    }

    private struct ForecastGrid: Decodable {
        let validAt: Date
        let coordinates: [[Int]]

        enum CodingKeys: String, CodingKey {
            case validAt = "Forecast Time"
            case coordinates
        }
    }
}
