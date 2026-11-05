import Foundation

protocol VIIRSImageryServiceProtocol: Service {
    func getAvailableDates(for product: VIIRSImageryService.Product) async throws -> [String]
}

/// VIIRS imagery published by NASA GIBS in Web Mercator.
struct VIIRSImageryService: VIIRSImageryServiceProtocol {
    enum Product: String {
        case trueColour = "VIIRS_NOAA21_CorrectedReflectance_TrueColor"
        case nightLights = "VIIRS_NOAA20_GapFilled_BRDF_Corrected_DayNightBand_Radiance"

        var maximumZoom: Int { self == .trueColour ? 9 : 8 }
        fileprivate var matrix: String { "GoogleMapsCompatible_Level\(maximumZoom)" }
        fileprivate var fileExtension: String { self == .trueColour ? "jpg" : "png" }
        fileprivate var lookbackDays: Int { self == .trueColour ? 7 : 30 }
    }

    var rootURL: String { Self.endpointRoot }
    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory

    private static let endpointRoot = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best"
    private static let dayFormat = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
    }

    func getAvailableDates(for product: Product) async throws -> [String] {
        let now = Date()
        let days = (0..<product.lookbackDays).map { Self.dayFormat.format(now.addingTimeInterval(-Double($0) * 86_400)) }
        let endpoint = DomainsEndpoint(product: product, firstDay: days[days.count - 1])
        let request = try requestFactory.createURLRequest(root: rootURL, endpoint: endpoint)
        let data: Data = try await networkService.send(request: request)
        return try Self.availableDates(in: data, within: days)
    }

    static func tileTemplate(for product: Product, date: String) -> String {
        "\(endpointRoot)/\(product.rawValue)/default/\(date)/\(product.matrix)/{z}/{y}/{x}.\(product.fileExtension)"
    }

    static func availableDates(in data: Data, within days: [String]) throws -> [String] {
        let delegate = DomainParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw HTTPError.invalidResponse }

        // GIBS describes daily coverage as comma-separated dates or start/end/P1D ranges.
        let periods = delegate.domain.split(separator: ",").compactMap { period -> ClosedRange<String>? in
            let parts = period.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/")
            guard let first = parts.first,
                  parts.count == 1 || (parts.count == 3 && parts[2] == "P1D") else { return nil }
            let start = String(first)
            let end = parts.count == 1 ? start : String(parts[1])
            guard (try? dayFormat.parse(start)) != nil, (try? dayFormat.parse(end)) != nil,
                  start <= end else { return nil }
            return start...end
        }
        let dates = days.filter { day in periods.contains { $0.contains(day) } }
        guard !dates.isEmpty else { throw HTTPError.invalidResponse }
        return dates
    }

    private struct DomainsEndpoint: Endpoint {
        let product: Product
        let firstDay: String
        let httpMethod: HTTPMethod = .get

        var path: String {
            "/1.0.0/\(product.rawValue)/default/\(product.matrix)/all/\(firstDay)--.xml"
        }
    }

    private final class DomainParser: NSObject, XMLParserDelegate {
        var domain = ""
        private var readingDomain = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes attributeDict: [String: String]) {
            if elementName == "Domain" { readingDomain = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if readingDomain { domain += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            if elementName == "Domain" { readingDomain = false }
        }
    }
}
