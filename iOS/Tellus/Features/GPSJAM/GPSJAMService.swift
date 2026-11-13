import Foundation
import zlib

protocol GPSJAMServiceProtocol: Service {
    func getOverlay(for day: Date?) async throws -> GPSJAMOverlay
}

actor GPSJAMService: GPSJAMServiceProtocol {
    nonisolated let rootURL = "https://gpsjam.org"
    private let networkService: NetworkServiceProtocol
    private let requestFactory: URLRequestFactory
    private let cache = NSCache<NSString, GPSJAMOverlay>()

    init(networkService: NetworkServiceProtocol, requestFactory: URLRequestFactory = .default) {
        self.networkService = networkService
        self.requestFactory = requestFactory
        cache.countLimit = 3
    }

    func getOverlay(for day: Date?) async throws -> GPSJAMOverlay {
        let dates = day.map { [$0] } ?? Self.recentDays()
        for date in dates {
            try Task.checkCancellation()
            let label = Self.dayLabel(date)
            if let cached = cache.object(forKey: label as NSString) { return cached }
            do {
                let request = try requestFactory.createURLRequest(root: rootURL, endpoint: DailyFile(day: label))
                let data: Data = try await networkService.send(request: request)
                try Task.checkCancellation()
                let cells = try GPSJAMDailyFile.cells(from: data, day: label)
                let overlay = GPSJAMOverlay(day: label, cells: cells)
                try Task.checkCancellation()
                cache.setObject(overlay, forKey: label as NSString)
                return overlay
            } catch HTTPError.invalidStatus(let code, _) where code == 404 || code == 410 {
                // The newest day can still be pending publication.
                continue
            }
        }
        throw GPSJAMDailyFile.Unavailable()
    }

    static func recentDays(before date: Date = .now) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let today = calendar.startOfDay(for: date)
        return (1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    static func dayLabel(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private struct DailyFile: Endpoint {
        let day: String
        let httpMethod: HTTPMethod = .get
        var path: String { "/data/\(day)-h3_4.csv" }
    }
}

enum GPSJAMDailyFile {
    struct Unavailable: Error {}

    static func cells(from data: Data, day: String) throws -> [GPSJAMCell] {
        let csv = try data.starts(with: [0x1f, 0x8b]) ? gunzip(data) : data
        guard let text = String(data: csv, encoding: .utf8) else { throw HTTPError.invalidResponse }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.first == "hex,count_good_aircraft,count_bad_aircraft" else {
            throw HTTPError.invalidResponse
        }

        var hasObservations = false
        let cells = lines.dropFirst().compactMap { line -> GPSJAMCell? in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 3, let index = UInt64(fields[0], radix: 16),
                  let good = UInt32(fields[1]), let bad = UInt32(fields[2]),
                  good > 0 || bad > 0 else { return nil }
            hasObservations = true
            let cell = GPSJAMCell(index: index, day: day, good: Int(good), bad: Int(bad))
            return cell.level == nil ? nil : cell
        }
        guard hasObservations else { throw HTTPError.invalidResponse }
        return cells
    }

    // URLSession handles HTTP content encoding. Some responses carry gzip
    // bytes as the file itself, so also recognize the gzip signature.
    private static func gunzip(_ data: Data) throws -> Data {
        let limit = 8 * 1024 * 1024
        guard data.count <= limit else { throw HTTPError.invalidResponse }
        return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Data in
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = UInt32(input.count)
            guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw HTTPError.invalidResponse
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var chunk = [UInt8](repeating: 0, count: 32 * 1024)
            var status: Int32
            repeat {
                status = chunk.withUnsafeMutableBufferPointer { buffer in
                    stream.next_out = buffer.baseAddress
                    stream.avail_out = UInt32(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let count = chunk.count - Int(stream.avail_out)
                guard status == Z_OK || status == Z_STREAM_END, output.count + count <= limit else {
                    throw HTTPError.invalidResponse
                }
                output.append(contentsOf: chunk.prefix(count))
            } while status != Z_STREAM_END
            return output
        }
    }
}
