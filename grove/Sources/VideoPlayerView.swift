import SwiftUI
import AVKit
import AVFoundation

/// A video player wrapper that tracks playback time and supports seek-to-timestamp.
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    @Binding var currentTime: Double
    @Binding var duration: Double
    let seekToTime: Double?

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        let player = AVPlayer(url: url)
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true

        // Observe duration once asset is ready
        let asset = player.currentItem?.asset
        Task { @MainActor in
            if let asset = asset {
                if let dur = try? await asset.load(.duration) {
                    let secs = CMTimeGetSeconds(dur)
                    if secs.isFinite {
                        duration = secs
                    }
                }
            }
        }

        // Periodic time observer for tracking playback position
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        let currentTimeBinding = _currentTime
        let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            MainActor.assumeIsolated {
                let secs = CMTimeGetSeconds(time)
                if secs.isFinite {
                    currentTimeBinding.wrappedValue = secs
                }
            }
        }
        context.coordinator.timeObserver = observer
        context.coordinator.player = player

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Handle seek requests
        if let seekTo = seekToTime, seekTo != context.coordinator.lastSeekTime {
            context.coordinator.lastSeekTime = seekTo
            let cmTime = CMTime(seconds: seekTo, preferredTimescale: 600)
            nsView.player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        if let observer = coordinator.timeObserver, let player = coordinator.player {
            player.removeTimeObserver(observer)
        }
        nsView.player?.pause()
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var player: AVPlayer?
        var timeObserver: Any?
        var lastSeekTime: Double?
    }
}

// MARK: - Timestamp Formatting

extension Double {
    /// Format seconds as HH:MM:SS or MM:SS
    var formattedTimestamp: String {
        guard self.isFinite && self >= 0 else { return "0:00" }
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Thumbnail Generator

enum VideoThumbnailGenerator {
    /// Generate a thumbnail from a local video file at the given time (default: midpoint or 1 second).
    static func generateThumbnail(for url: URL, at time: CMTime? = nil) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)

        let targetTime: CMTime
        if let time = time {
            targetTime = time
        } else {
            // Try midpoint, fallback to 1 second
            if let duration = try? await asset.load(.duration) {
                let mid = CMTimeGetSeconds(duration) / 2.0
                targetTime = CMTime(seconds: max(mid, 0.5), preferredTimescale: 600)
            } else {
                targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
            }
        }

        do {
            let (cgImage, _) = try await generator.image(at: targetTime)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                return nil
            }
            return jpegData
        } catch {
            return nil
        }
    }

    /// Extract video metadata (duration, dimensions) from a local file.
    static func extractMetadata(for url: URL) async -> [String: String] {
        var meta: [String: String] = [:]
        let asset = AVURLAsset(url: url)

        if let duration = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(duration)
            if secs.isFinite {
                meta["videoDuration"] = String(format: "%.1f", secs)
            }
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first {
            if let size = try? await track.load(.naturalSize) {
                meta["videoWidth"] = "\(Int(size.width))"
                meta["videoHeight"] = "\(Int(size.height))"
            }
        }

        meta["videoLocalFile"] = "true"
        return meta
    }
}
