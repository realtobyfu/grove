import Foundation
import Testing
@testable import grove

struct CaptureServiceURLTests {

    // MARK: - arXiv identifiers

    @Test func arxivIDFromAbsURL() throws {
        let url = try #require(URL(string: "https://arxiv.org/abs/2401.12345"))
        #expect(CaptureService.arxivID(from: url) == "2401.12345")
    }

    @Test func arxivIDFromPDFURL() throws {
        let url = try #require(URL(string: "https://arxiv.org/pdf/2401.12345"))
        #expect(CaptureService.arxivID(from: url) == "2401.12345")
    }

    @Test func arxivIDFromPDFURLWithExtension() throws {
        let url = try #require(URL(string: "https://arxiv.org/pdf/2401.12345.pdf"))
        #expect(CaptureService.arxivID(from: url) == "2401.12345")
    }

    @Test func arxivIDStripsVersionSuffix() throws {
        let abs = try #require(URL(string: "https://arxiv.org/abs/2401.12345v3"))
        #expect(CaptureService.arxivID(from: abs) == "2401.12345")

        let pdf = try #require(URL(string: "https://arxiv.org/pdf/2401.12345v12.pdf"))
        #expect(CaptureService.arxivID(from: pdf) == "2401.12345")
    }

    @Test func arxivIDHandlesFiveDigitNewStyleIDs() throws {
        let url = try #require(URL(string: "https://arxiv.org/abs/2401.123456"))
        // Six digits is not a valid new-style identifier.
        #expect(CaptureService.arxivID(from: url) == nil)

        let valid = try #require(URL(string: "https://arxiv.org/abs/0704.00011"))
        #expect(CaptureService.arxivID(from: valid) == "0704.00011")
    }

    @Test func arxivIDHandlesOldStyleIDs() throws {
        let cs = try #require(URL(string: "https://arxiv.org/abs/cs/0112017"))
        #expect(CaptureService.arxivID(from: cs) == "cs/0112017")

        let subject = try #require(URL(string: "https://arxiv.org/abs/math.GT/0309136"))
        #expect(CaptureService.arxivID(from: subject) == "math.GT/0309136")

        let versioned = try #require(URL(string: "https://arxiv.org/pdf/cond-mat/0112017v2"))
        #expect(CaptureService.arxivID(from: versioned) == "cond-mat/0112017")
    }

    @Test func arxivIDAcceptsAlternateHosts() throws {
        let hosts = [
            "https://www.arxiv.org/abs/2401.12345",
            "https://export.arxiv.org/abs/2401.12345",
            "https://ar5iv.labs.arxiv.org/html/2401.12345",
            "https://ar5iv.org/abs/2401.12345",
        ]
        for host in hosts {
            let url = try #require(URL(string: host))
            #expect(CaptureService.arxivID(from: url) == "2401.12345", "failed for \(host)")
        }
    }

    @Test func arxivIDIgnoresNonPaperURLs() throws {
        let negatives = [
            "https://arxiv.org/",
            "https://arxiv.org/list/cs.AI/recent",
            "https://arxiv.org/abs/",
            "https://arxiv.org/abs/not-an-id",
            "https://example.com/abs/2401.12345",
            "https://myarxiv.org/abs/2401.12345",
            "https://openreview.net/forum?id=abc",
        ]
        for negative in negatives {
            let url = try #require(URL(string: negative))
            #expect(CaptureService.arxivID(from: url) == nil, "expected nil for \(negative)")
        }
    }

    // MARK: - Normalized URL dedupe key

    @Test func normalizedURLCollapsesArxivSurfaces() {
        let expected = "https://arxiv.org/abs/2401.12345"
        let variants = [
            "https://arxiv.org/abs/2401.12345",
            "https://arxiv.org/pdf/2401.12345",
            "https://arxiv.org/pdf/2401.12345.pdf",
            "https://arxiv.org/abs/2401.12345v2",
            "https://www.arxiv.org/pdf/2401.12345v9.pdf",
            "https://ar5iv.labs.arxiv.org/html/2401.12345",
        ]
        for variant in variants {
            #expect(CaptureService.normalizedURLString(variant) == expected, "failed for \(variant)")
        }
    }

    @Test func normalizedURLKeepsDistinctArxivPapersApart() {
        #expect(
            CaptureService.normalizedURLString("https://arxiv.org/abs/2401.12345")
                != CaptureService.normalizedURLString("https://arxiv.org/abs/2401.12346")
        )
    }

    @Test func normalizedURLStillStripsTrackingParamsForNonArxiv() {
        #expect(
            CaptureService.normalizedURLString("https://example.com/post/?utm_source=x")
                == "https://example.com/post"
        )
    }

    // MARK: - Video source + ID

    @Test func youTubeWatchURL() throws {
        let url = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s"))
        let result = try #require(CaptureService.videoSourceAndID(from: url))
        #expect(result.source == "youtube")
        #expect(result.id == "dQw4w9WgXcQ")
    }

    @Test func youTubeShortLinkURL() throws {
        let url = try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ?t=30"))
        let result = try #require(CaptureService.videoSourceAndID(from: url))
        #expect(result.source == "youtube")
        #expect(result.id == "dQw4w9WgXcQ")
    }

    @Test func youTubeShortsLiveAndEmbedURLs() throws {
        let forms = [
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://youtube.com/live/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
        ]
        for form in forms {
            let url = try #require(URL(string: form))
            let result = try #require(CaptureService.videoSourceAndID(from: url), "failed for \(form)")
            #expect(result.source == "youtube")
            #expect(result.id == "dQw4w9WgXcQ")
        }
    }

    @Test func youTubeAlternateHosts() throws {
        let forms = [
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/watch?v=dQw4w9WgXcQ",
        ]
        for form in forms {
            let url = try #require(URL(string: form))
            let result = try #require(CaptureService.videoSourceAndID(from: url), "failed for \(form)")
            #expect(result.source == "youtube")
            #expect(result.id == "dQw4w9WgXcQ")
        }
    }

    @Test func vimeoURLs() throws {
        let direct = try #require(URL(string: "https://vimeo.com/123456789"))
        let directResult = try #require(CaptureService.videoSourceAndID(from: direct))
        #expect(directResult.source == "vimeo")
        #expect(directResult.id == "123456789")

        let player = try #require(URL(string: "https://player.vimeo.com/video/123456789"))
        let playerResult = try #require(CaptureService.videoSourceAndID(from: player))
        #expect(playerResult.source == "vimeo")
        #expect(playerResult.id == "123456789")
    }

    // MARK: - Video classification

    @Test func videoClassificationCoversEveryRecognizedSurface() {
        let videos = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://youtube.com/shorts/dQw4w9WgXcQ",
            "https://www.youtube.com/live/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
            "https://www.youtube.com/v/dQw4w9WgXcQ",
            "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
            "https://youtube-nocookie.com/embed/dQw4w9WgXcQ",
            "https://m.youtube.com/shorts/dQw4w9WgXcQ",
            "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://vimeo.com/123456789",
            "https://player.vimeo.com/video/123456789",
        ]
        for video in videos {
            #expect(CaptureService.isVideoURL(video), "expected video for \(video)")
        }
    }

    @Test func videoClassificationKeepsProviderlessVideoPages() {
        // No oEmbed provider, but these were classified `.video` before and
        // must stay that way.
        let videos = [
            "https://www.twitch.tv/somestreamer",
            "https://vimeo.com/channels/staffpicks",
        ]
        for video in videos {
            #expect(CaptureService.isVideoURL(video), "expected video for \(video)")
        }
    }

    @Test func videoClassificationIgnoresNonVideoURLs() {
        let negatives = [
            "https://arxiv.org/abs/2401.12345",
            "https://github.com/apple/swift",
            "https://example.com/post",
            "https://example.com/shorts/dQw4w9WgXcQ",
            "https://notyoutube.example.com/embed/dQw4w9WgXcQ",
        ]
        for negative in negatives {
            #expect(!CaptureService.isVideoURL(negative), "expected non-video for \(negative)")
        }
    }

    @Test func videoSourceIgnoresUnsupportedURLs() throws {
        let negatives = [
            "https://www.twitch.tv/somestreamer",
            "https://www.youtube.com/watch",
            "https://www.youtube.com/feed/subscriptions",
            "https://www.youtube.com/@somechannel",
            "https://vimeo.com/channels/staffpicks",
            "https://example.com/watch?v=dQw4w9WgXcQ",
            "https://arxiv.org/abs/2401.12345",
        ]
        for negative in negatives {
            let url = try #require(URL(string: negative))
            #expect(CaptureService.videoSourceAndID(from: url) == nil, "expected nil for \(negative)")
        }
    }
}
