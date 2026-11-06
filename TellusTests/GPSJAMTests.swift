import MapKit
import XCTest
@testable import Tellus

final class GPSJAMTests: XCTestCase {
    func testGzipFileProducesSelectableHex() throws {
        let data = try XCTUnwrap(Data(base64Encoded:
            "H4sIAAAAAAAC/8tIrdBJzi/NK4lPz89PiU/MLEouSkwrgYolJSKEuCxMjCyMDSzToEDHwkDHyAAqmgQXNTQw0DHkAgDdkX/QVwAAAA=="
        ))
        let cells = try GPSJAMDailyFile.cells(from: data, day: "2026-11-04")
        XCTAssertEqual(cells.count, 1)

        let overlay = GPSJAMOverlay(day: "2026-11-04", cells: cells)
        let sanFrancisco = CLLocationCoordinate2D(latitude: 37.775, longitude: -122.419)
        let cell = try XCTUnwrap(overlay.cell(at: sanFrancisco))
        XCTAssertEqual(cell.level, .high)
        XCTAssertEqual(cell.total, 100)
        XCTAssertEqual(cell.bad, 20)
        XCTAssertEqual(cell.observedShare, 0.20)
        XCTAssertEqual(cell.adjustedShare, 0.19)
        XCTAssertEqual(overlay.shapes[.high]?.count, 1)
    }

    func testAdjustedThresholds() {
        let singleReport = GPSJAMCell(index: 0, day: "", good: 0, bad: 1)
        let sparseCell = GPSJAMCell(index: 0, day: "", good: 0, bad: 4)
        let twoPercent = GPSJAMCell(index: 0, day: "", good: 97, bad: 3)
        let tenPercent = GPSJAMCell(index: 0, day: "", good: 89, bad: 11)
        let aboveTenPercent = GPSJAMCell(index: 0, day: "", good: 88, bad: 12)

        XCTAssertNil(singleReport.level)
        XCTAssertNil(sparseCell.level)
        XCTAssertEqual(twoPercent.level, .elevated)
        XCTAssertEqual(tenPercent.level, .elevated)
        XCTAssertEqual(aboveTenPercent.level, .high)
    }

    func testDatePickerUsesOnlyCompletedUTCDays() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T23:55:00Z"))
        let days = GPSJAMService.recentDays(before: now).map(GPSJAMService.dayLabel)
        XCTAssertEqual(days, [
            "2026-10-31", "2026-10-30", "2026-10-29", "2026-10-28",
            "2026-10-27", "2026-10-26", "2026-10-25",
        ])
    }

    func testCorruptGzipIsRejected() {
        XCTAssertThrowsError(try GPSJAMDailyFile.cells(from: Data([0x1f, 0x8b, 0, 0]), day: "2026-11-04"))
    }
}
