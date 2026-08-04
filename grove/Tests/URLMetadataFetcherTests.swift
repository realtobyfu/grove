import Foundation
import Testing
@testable import grove

struct URLMetadataFetcherTests {

    // MARK: - ISO-8601 duration (schema.org `itemprop="duration"`)

    @Test func parsesFullAndPartialDurations() {
        #expect(URLMetadataFetcher.parseISO8601Duration("PT4M13S") == 253)
        #expect(URLMetadataFetcher.parseISO8601Duration("PT1H2M3S") == 3723)
        #expect(URLMetadataFetcher.parseISO8601Duration("PT2H") == 7200)
        #expect(URLMetadataFetcher.parseISO8601Duration("PT45S") == 45)
        #expect(URLMetadataFetcher.parseISO8601Duration("PT1H30S") == 3630)
        #expect(URLMetadataFetcher.parseISO8601Duration("PT0S") == 0)
        #expect(URLMetadataFetcher.parseISO8601Duration(" pt4m13s ") == 253)
    }

    @Test func rejectsMalformedDurations() {
        let garbage = [
            "",
            "PT",
            "4M13S",
            "PT90",
            "P1D",
            "PTXS",
            "PT4M13",
            "not a duration",
        ]
        for value in garbage {
            #expect(URLMetadataFetcher.parseISO8601Duration(value) == nil, "expected nil for \(value)")
        }
    }
}
