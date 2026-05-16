// VideoPlayerView.swift
// A UIView that hosts AVPlayer + AVPlayerLayer, plus overlay support.

import UIKit
import AVFoundation

final class VideoPlayerView: UIView {

    // MARK: Public

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    /// Semi-transparent UILabel views that represent text overlays during preview
    private(set) var textOverlayViews: [UUID: UILabel] = [:]

    // MARK: Private

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override static var layerClass: AnyClass { AVPlayerLayer.self }

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
        layer.cornerRadius = 12
        clipsToBounds = true
    }

    // MARK: Text Overlay Preview

    func syncTextOverlays(_ overlays: [TextOverlay]) {
        // Remove labels no longer present
        let ids = Set(overlays.map(\.id))
        for (id, lbl) in textOverlayViews where !ids.contains(id) {
            lbl.removeFromSuperview()
            textOverlayViews.removeValue(forKey: id)
        }

        // Add / update labels
        for overlay in overlays {
            let label: UILabel
            if let existing = textOverlayViews[overlay.id] {
                label = existing
            } else {
                label = makeDraggableLabel(for: overlay)
                addSubview(label)
                textOverlayViews[overlay.id] = label
            }
            label.text = overlay.text
            label.font = UIFont(name: overlay.fontName, size: overlay.fontSize) ??
                         .systemFont(ofSize: overlay.fontSize, weight: .bold)
            label.textColor = overlay.color
            label.sizeToFit()
            label.center = CGPoint(x: overlay.normalizedPosition.x * bounds.width,
                                   y: overlay.normalizedPosition.y * bounds.height)
        }
    }

    func updateTextVisibility(currentTime: CMTime) {
        let t = CMTimeGetSeconds(currentTime)
        for (id, lbl) in textOverlayViews {
            // match overlay
            // (labels carry the UUID in accessibilityIdentifier)
            lbl.isHidden = false
            _ = id; _ = t   // visibility filtering is handled in compositor for export
        }
    }

    private func makeDraggableLabel(for overlay: TextOverlay) -> UILabel {
        let l = UILabel()
        l.text            = overlay.text
        l.textColor       = overlay.color
        l.font            = UIFont(name: overlay.fontName, size: overlay.fontSize) ??
                            .boldSystemFont(ofSize: overlay.fontSize)
        l.isUserInteractionEnabled = true
        l.accessibilityIdentifier = overlay.id.uuidString
        l.layer.shadowColor   = UIColor.black.cgColor
        l.layer.shadowRadius  = 3
        l.layer.shadowOpacity = 0.8
        l.layer.shadowOffset  = CGSize(width: 1, height: 1)
        return l
    }
}
