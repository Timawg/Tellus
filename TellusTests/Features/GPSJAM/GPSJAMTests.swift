import MapKit
import Testing
@testable import Tellus

@Suite
struct GPSJAMTests {
    @Test func gzipFileProducesSelectableHex() throws {
        let data = try #require(Data(base64Encoded:
            "H4sIAAAAAAAC/8tIrdBJzi/NK4lPz89PiU/MLEouSkwrgYolJSKEuCxMjCyMDSzToEDHwkDHyAAqmgQXNTQw0DHkAgDdkX/QVwAAAA=="
        ))
        let cells = try GPSJAMDailyFile.cells(from: data, day: "2026-11-04")
        #expect(cells.count == 1)

        let overlay = GPSJAMOverlay(day: "2026-11-04", cells: cells)
        let sanFrancisco = CLLocationCoordinate2D(latitude: 37.775, longitude: -122.419)
        let cell = try #require(overlay.cell(at: sanFrancisco))
        #expect(cell.level == .high)
        #expect(cell.total == 100)
        #expect(cell.bad == 20)
        #expect(cell.observedShare == 0.20)
        #expect(cell.adjustedShare == 0.19)
        #expect(overlay.shapes[.high]?.count == 1)
    }

    @Test func adjustedThresholds() {
        let singleReport = GPSJAMCell(index: 0, day: "", good: 0, bad: 1)
        let sparseCell = GPSJAMCell(index: 0, day: "", good: 0, bad: 4)
        let twoPercent = GPSJAMCell(index: 0, day: "", good: 97, bad: 3)
        let tenPercent = GPSJAMCell(index: 0, day: "", good: 89, bad: 11)
        let aboveTenPercent = GPSJAMCell(index: 0, day: "", good: 88, bad: 12)

        #expect(singleReport.level == nil)
        #expect(sparseCell.level == nil)
        #expect(twoPercent.level == .elevated)
        #expect(tenPercent.level == .elevated)
        #expect(aboveTenPercent.level == .high)
    }

    @Test func datePickerUsesOnlyCompletedUTCDays() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-01T23:55:00Z"))
        let days = GPSJAMService.recentDays(before: now).map(GPSJAMService.dayLabel)
        #expect(days == [
            "2026-10-31", "2026-10-30", "2026-10-29", "2026-10-28",
            "2026-10-27", "2026-10-26", "2026-10-25",
        ])
    }

    @Test func corruptGzipIsRejected() {
        #expect(throws: (any Error).self) {
            _ = try GPSJAMDailyFile.cells(from: Data([0x1f, 0x8b, 0, 0]), day: "2026-11-04")
        }
    }
}
