// VideoFilterCompositor.swift
// Applies CIFilters, blur, and text overlays in a custom AVVideoCompositing pass.

import AVFoundation
import CoreImage
import CoreText
import UIKit

// MARK: - Custom Compositor

final class VideoFilterCompositor: NSObject, AVVideoCompositing {

    private struct RenderSettings {
        var filter: VideoFilter = .none
        var blurType: BlurType = .none
        var blurIntensity: Float = 8.0
        var textOverlays: [TextOverlay] = []
        var videoSize: CGSize = .zero
    }

    private static var activeSettings = RenderSettings()
    private static let settingsLock = NSLock()

    static func configure(from state: EditState, videoSize: CGSize) {
        settingsLock.lock()
        activeSettings = RenderSettings(
            filter: state.filter,
            blurType: state.blurType,
            blurIntensity: state.blurIntensity,
            textOverlays: state.textOverlays,
            videoSize: videoSize
        )
        settingsLock.unlock()
    }

    private static func settingsSnapshot() -> RenderSettings {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return activeSettings
    }

    // Shared CIContext – expensive to create, so kept as a static
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let renderQueue = DispatchQueue(label: "com.videoeditor.compositor",
                                            attributes: .concurrent)

    // MARK: AVVideoCompositing

    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self else { request.finish(with: makeError("Compositor deallocated")); return }
            let settings = Self.settingsSnapshot()

            guard let trackID = request.sourceTrackIDs.first,
                  let srcBuffer = request.sourceFrame(byTrackID: trackID.int32Value) else {
                request.finish(with: makeError("No source frame"))
                return
            }

            // ---- CI pipeline ----
            var image = CIImage(cvPixelBuffer: srcBuffer).clampedToExtent()
            image = settings.filter.apply(to: image)
            image = settings.blurType.apply(to: image, intensity: settings.blurIntensity)
            image = image.cropped(to: CIImage(cvPixelBuffer: srcBuffer).extent)

            guard let outputBuffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: makeError("newPixelBuffer failed"))
                return
            }

            VideoFilterCompositor.ciContext.render(image, to: outputBuffer)

            // ---- CoreGraphics text pass ----
            if !settings.textOverlays.isEmpty {
                self.drawText(settings.textOverlays, into: outputBuffer, at: request.compositionTime)
            }

            request.finish(withComposedVideoFrame: outputBuffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderQueue.async(flags: .barrier) {}
    }

    // MARK: Text Drawing (CoreGraphics into pixel buffer)

    private func drawText(_ textOverlays: [TextOverlay], into pixelBuffer: CVPixelBuffer, at time: CMTime) {
        let t = CMTimeGetSeconds(time)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
                         CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(data: base,
                                  width: w, height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo) else { return }

        // CG coordinate origin is bottom-left; our normalised origin is top-left
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        for overlay in textOverlays {
            let s = CMTimeGetSeconds(overlay.startTime)
            let e = CMTimeGetSeconds(overlay.endTime)
            guard t >= s && t <= e else { continue }

            let font = CTFontCreateWithName(overlay.fontName as CFString, overlay.fontSize, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            font,
                .foregroundColor: overlay.color.cgColor,
                .strokeColor:     overlay.strokeColor.cgColor,
                .strokeWidth:     -overlay.strokeWidth   // negative = fill + stroke
            ]
            let attrStr = NSAttributedString(string: overlay.text, attributes: attrs)
            let line    = CTLineCreateWithAttributedString(attrStr)
            let bounds  = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            let x = overlay.normalizedPosition.x * CGFloat(w) - bounds.width / 2
            let y = overlay.normalizedPosition.y * CGFloat(h) - bounds.height / 2

            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)
        }
    }
}

// MARK: - Helpers

private func makeError(_ msg: String) -> NSError {
    NSError(domain: "VideoFilterCompositor", code: -1,
            userInfo: [NSLocalizedDescriptionKey: msg])
}
