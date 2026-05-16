// VideoCompositionService.swift
// Builds AVMutableComposition + AVMutableVideoComposition from EditState,
// and drives AVAssetExportSession for final export.

import AVFoundation
import UIKit

// MARK: - Service

final class VideoCompositionService {

    // Shared compositor (holds filter / blur / text state)
    private let compositor = VideoFilterCompositor()

    // MARK: Build for Playback / Export

    /// Returns a configured (composition, videoComposition) ready to hand to AVPlayer
    /// or AVAssetExportSession.  Returns nil if the asset isn't ready.
    func build(from state: EditState) -> (AVMutableComposition, AVMutableVideoComposition)? {
        guard let asset = state.asset else { return nil }

        // ---- Composition ----
        let comp = AVMutableComposition()
        guard let srcVideo = asset.tracks(withMediaType: .video).first,
              let compVideo = comp.addMutableTrack(withMediaType: .video,
                                                   preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        // Resolve trim range
        let assetDuration = asset.duration
        let start = state.trimStart
        let end   = CMTIME_IS_INDEFINITE(state.trimEnd) ? assetDuration : state.trimEnd
        let rawRange = CMTimeRange(start: start, end: end)

        // Speed scaling: insert a shorter (or longer) time range
        // e.g. speed=2.0 → insert srcRange into half the duration
        let scaledDuration = CMTimeMultiplyByFloat64(rawRange.duration,
                                                      multiplier: Float64(1.0 / state.speed))
        let insertRange = CMTimeRange(start: start, duration: rawRange.duration)
        do {
            try compVideo.insertTimeRange(insertRange, of: srcVideo, at: .zero)
        } catch {
            print("VideoCompositionService: failed to insert video – \(error)")
            return nil
        }
        if state.speed != 1.0 {
            compVideo.scaleTimeRange(
                CMTimeRange(start: .zero, duration: rawRange.duration),
                toDuration: scaledDuration
            )
        }

        // Audio (optional)
        if let srcAudio = asset.tracks(withMediaType: .audio).first,
           let compAudio = comp.addMutableTrack(withMediaType: .audio,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compAudio.insertTimeRange(insertRange, of: srcAudio, at: .zero)
            if state.speed != 1.0 {
                compAudio.scaleTimeRange(
                    CMTimeRange(start: .zero, duration: rawRange.duration),
                    toDuration: scaledDuration
                )
            }
        }

        // ---- Video Composition ----
        let naturalSize = preferredTransformSize(track: srcVideo)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(30))

        let videoComp = AVMutableVideoComposition()
        videoComp.customVideoCompositorClass = VideoFilterCompositor.self
        videoComp.frameDuration = frameDuration
        videoComp.renderSize    = naturalSize

        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: comp.duration)

        // Apply preferred transform so portrait videos render correctly
        let layerInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        let transform   = srcVideo.preferredTransform
        layerInstr.setTransform(transform, at: .zero)
        instr.layerInstructions = [layerInstr]
        videoComp.instructions   = [instr]

        // Update compositor state
        compositor.filter        = state.filter
        compositor.blurType      = state.blurType
        compositor.blurIntensity = state.blurIntensity
        compositor.textOverlays  = state.textOverlays
        compositor.videoSize     = naturalSize

        // The custom compositor class is referenced by class, but AVFoundation
        // instantiates it fresh.  We surface state through UserInfo on the composition.
        // Instead, we store a reference for the player path and patch through
        // the instruction's passthrough dict (see note below).
        // For simplicity, this service is the compositor's delegate via a
        // thread-safe singleton registry.
        CompositorRegistry.shared.register(compositor, for: videoComp)

        return (comp, videoComp)
    }

    // MARK: Export

    func export(state: EditState,
                options: ExportOptions,
                progress: @escaping (Float) -> Void,
                completion: @escaping (Result<URL, Error>) -> Void) {

        guard let (comp, videoComp) = build(from: state) else {
            completion(.failure(ExportError.compositionFailed))
            return
        }

        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("edited_\(UUID().uuidString).mp4")

        guard let session = AVAssetExportSession(asset: comp,
                                                 presetName: options.quality.preset) else {
            completion(.failure(ExportError.sessionFailed))
            return
        }

        session.outputURL          = outputURL
        session.outputFileType     = .mp4
        session.videoComposition   = videoComp
        session.shouldOptimizeForNetworkUse = true

        // Progress timer
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progress(session.progress)
        }

        session.exportAsynchronously {
            timer.invalidate()
            switch session.status {
            case .completed:
                completion(.success(outputURL))
            case .failed:
                completion(.failure(session.error ?? ExportError.unknown))
            case .cancelled:
                completion(.failure(ExportError.cancelled))
            default:
                completion(.failure(ExportError.unknown))
            }
        }
    }

    // MARK: Helpers

    private func preferredTransformSize(track: AVAssetTrack) -> CGSize {
        let t    = track.preferredTransform
        let size = track.naturalSize.applying(t)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case compositionFailed, sessionFailed, cancelled, unknown

    var errorDescription: String? {
        switch self {
        case .compositionFailed: return "Could not build video composition."
        case .sessionFailed:     return "Could not create export session."
        case .cancelled:         return "Export was cancelled."
        case .unknown:           return "An unknown export error occurred."
        }
    }
}

// MARK: - Compositor Registry
// AVFoundation instantiates the compositor class itself; we use a registry
// keyed on the videoComposition object to pass state across.

final class CompositorRegistry {
    static let shared = CompositorRegistry()
    private var map = [ObjectIdentifier: VideoFilterCompositor]()
    private let lock = NSLock()

    func register(_ compositor: VideoFilterCompositor, for comp: AVMutableVideoComposition) {
        lock.lock(); defer { lock.unlock() }
        map[ObjectIdentifier(comp)] = compositor
    }

    func compositor(for comp: AVVideoComposition) -> VideoFilterCompositor? {
        lock.lock(); defer { lock.unlock() }
        return map[ObjectIdentifier(comp)]
    }
}
