import Foundation
import Testing
@testable import Tellus

struct TravelAdviceTests {
    private static let advisoryHTML = """
        <div class="AdvisoryContainer ExHigh">
          <h3>Countrywide guidance</h3>
          <p><a href="#levels">Exercise caution</a> when travelling.</p>
        </div>
        <div class="AdvisoryContainer RegionalAdv">
          <h3>Northern region &ndash; Avoid non-essential travel</h3>
          <ul>
            <li>North province, excluding:</li>
            <ul>
              <li>North city, if reached through:</li>
              <ul><li>the airport</li></ul>
            </ul>
            <li>West province</li>
          </ul>
          <p><a href='/travelling/advisories'>Official guidance</a></p>
        </div>
        """

    @Test func advisoryTopicsPreserveRegionalExceptionsAndLinks() throws {
        let information = Information(
            name: "Example",
            urlSlug: "example",
            geoGroup: "",
            friendlyDate: "",
            advisoryText: "Exercise caution",
            recentUpdates: "",
            advisories: Self.advisoryHTML,
            security: "",
            entryExit: "<h3>Border procedures</h3><p>Check the entry rules.</p>",
            health: "",
            lawsCulture: "",
            disastersClimate: "",
            officesHelpAbroad: .init(openingText: nil, closingText: nil),
            officesHTML: "",
            offices: []
        )
        let guide = DestinationGuide(information: information)
        #expect(guide.advisories.map(\.title) == [
            "Countrywide guidance", "Northern region – Avoid non-essential travel"
        ])
        #expect(guide.sections(for: .entry).map(\.title) == ["Border procedures"])
        let nationwide = try #require(guide.advisories.first)
        #expect(nationwide.blocks == [.paragraph(AttributedString("Exercise caution when travelling."))])

        let regional = try #require(guide.advisories.last)
        #expect(Array(regional.blocks.dropLast()) == [
            .bullet(AttributedString("North province, excluding:"), depth: 0),
            .bullet(AttributedString("North city, if reached through:"), depth: 1),
            .bullet(AttributedString("the airport"), depth: 2),
            .bullet(AttributedString("West province"), depth: 0)
        ])
        let linkBlock = try #require(regional.blocks.last)
        var link = AttributedString("Official guidance")
        link.link = URL(string: "https://travel.gc.ca/travelling/advisories")
        #expect(linkBlock == .paragraph(link))
    }
}
