// ThumbnailTimelineView.swift
// CapCut-style timeline: video thumbnails scroll under a fixed centre playhead.
// Left / right trim handles bracket the active region with a coloured border.

import UIKit
import AVFoundation

// MARK: - Delegate

protocol ThumbnailTimelineDelegate: AnyObject {
    func timeline(_ view: ThumbnailTimelineView, didScrollTo time: CMTime)
    func timeline(_ view: ThumbnailTimelineView, didChangeTrimStart time: CMTime)
    func timeline(_ view: ThumbnailTimelineView, didChangeTrimEnd time: CMTime)
    func timelineDidBeginScrubbing(_ view: ThumbnailTimelineView)
    func timelineDidEndScrubbing(_ view: ThumbnailTimelineView)
}

// MARK: - View

final class ThumbnailTimelineView: UIView {

    // MARK: Public API

    weak var delegate: ThumbnailTimelineDelegate?

    /// Call once when the asset is known.
    func configure(asset: AVAsset, duration: CMTime) {
        self.duration    = duration
        self.durationSec = CMTimeGetSeconds(duration)
        self.asset       = asset
        trimStartSec     = 0
        trimEndSec       = durationSec
        currentTimeSec   = 0
        hasPositionedInitialContentOffset = false
        generateThumbnails()
        setNeedsLayout()
    }

    /// Sync the playhead without triggering delegate callbacks.
    func setCurrentTime(_ time: CMTime, animated: Bool) {
        scrollToTimeSec(CMTimeGetSeconds(time), animated: animated, notifyDelegate: false)
    }

    func setTrimStart(_ time: CMTime) {
        trimStartSec = max(0, CMTimeGetSeconds(time))
        updateTrimHandles()
        setNeedsDisplay()
    }

    func setTrimEnd(_ time: CMTime) {
        trimEndSec = min(durationSec, CMTimeGetSeconds(time))
        updateTrimHandles()
        setNeedsDisplay()
    }

    // MARK: Constants

    private let thumbH:      CGFloat = 60
    private let thumbW:      CGFloat = 46
    private let handleW:     CGFloat = 18
    private let handleColor          = UIColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1)   // CapCut-style yellow
    private let accent               = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)

    // MARK: State

    private var asset:        AVAsset?
    private var duration:     CMTime  = .zero
    private var durationSec:  Double  = 0
    private var trimStartSec: Double  = 0
    private var trimEndSec:   Double  = 0
    private var currentTimeSec: Double = 0
    private var thumbCount:   Int     = 20
    private var isSyncingFromPlayer = false
    private var isDraggingLeft  = false
    private var isDraggingRight = false
    private var hasPositionedInitialContentOffset = false
    private var lastLayoutBoundsSize: CGSize = .zero

    private var pixelsPerSecond: CGFloat {
        guard durationSec > 0 else { return 1 }
        return (thumbW * CGFloat(thumbCount)) / CGFloat(durationSec)
    }

    // MARK: Subviews

    private let scrollView: UIScrollView = {
        let s = UIScrollView()
        s.showsHorizontalScrollIndicator = false
        s.showsVerticalScrollIndicator   = false
        s.alwaysBounceHorizontal         = true
        s.clipsToBounds                  = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let thumbStrip: UIView = {
        let v = UIView()
        v.clipsToBounds = true
        v.layer.cornerRadius = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var thumbImageViews: [UIImageView] = []

    // Trim border overlay (drawn as a CAShapeLayer over thumbStrip)
    private let trimBorderLayer = CAShapeLayer()

    // Left / right handles (positioned over the scroll view, gestures on self)
    private let leftHandle  = TrimHandleView(side: .left)
    private let rightHandle = TrimHandleView(side: .right)

    // Fixed playhead line (centre of the view)
    private let playheadLine: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 1
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = false
        return v
    }()

    // Time label that floats above playhead
    private let currentTimeLabel: UILabel = {
        let l = UILabel()
        l.text = "0:00"
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        l.textAlignment = .center
        l.layer.cornerRadius = 4
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isUserInteractionEnabled = false
        return l
    }()

    // Dashed trim time labels
    private let trimStartLabel = floatingTimeLabel()
    private let trimEndLabel   = floatingTimeLabel()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        clipsToBounds = false

        // Scroll view
        scrollView.delegate = self
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.centerYAnchor.constraint(equalTo: centerYAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: thumbH)
        ])

        // Thumbnail strip inside scroll view
        scrollView.addSubview(thumbStrip)

        // Trim border layer
        trimBorderLayer.fillColor   = UIColor.clear.cgColor
        trimBorderLayer.strokeColor = handleColor.cgColor
        trimBorderLayer.lineWidth   = 2.5
        layer.addSublayer(trimBorderLayer)

        // Handles
        [leftHandle, rightHandle].forEach { addSubview($0) }

        // Gestures on handles
        let leftPan  = UIPanGestureRecognizer(target: self, action: #selector(handleLeftPan(_:)))
        let rightPan = UIPanGestureRecognizer(target: self, action: #selector(handleRightPan(_:)))
        leftHandle.addGestureRecognizer(leftPan)
        rightHandle.addGestureRecognizer(rightPan)

        // Playhead + time
        addSubview(playheadLine)
        addSubview(currentTimeLabel)
        addSubview(trimStartLabel)
        addSubview(trimEndLabel)

        NSLayoutConstraint.activate([
            playheadLine.centerXAnchor.constraint(equalTo: centerXAnchor),
            playheadLine.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: -6),
            playheadLine.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            playheadLine.widthAnchor.constraint(equalToConstant: 2),

            currentTimeLabel.bottomAnchor.constraint(equalTo: scrollView.topAnchor, constant: -4),
            currentTimeLabel.centerXAnchor.constraint(equalTo: playheadLine.centerXAnchor),
            currentTimeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            currentTimeLabel.heightAnchor.constraint(equalToConstant: 20)
        ])

        trimStartLabel.isHidden = true
        trimEndLabel.isHidden   = true
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard durationSec > 0 else { return }

        let totalW = thumbW * CGFloat(thumbCount)
        let inset  = bounds.width / 2

        // Lay out thumb strip
        thumbStrip.frame = CGRect(x: 0, y: 0, width: totalW, height: thumbH)
        scrollView.contentSize = CGSize(width: totalW, height: thumbH)
        scrollView.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)

        // Position thumb image views inside strip
        for (i, iv) in thumbImageViews.enumerated() {
            iv.frame = CGRect(x: CGFloat(i) * thumbW, y: 0, width: thumbW, height: thumbH)
        }

        let boundsSizeChanged = lastLayoutBoundsSize != bounds.size
        lastLayoutBoundsSize = bounds.size
        if !hasPositionedInitialContentOffset || boundsSizeChanged {
            scrollToTimeSec(currentTimeSec, animated: false, notifyDelegate: false)
            hasPositionedInitialContentOffset = true
        }

        updateTrimHandles()
        updateTrimBorder()
    }

    // MARK: Handle Positions

    private func updateTrimHandles() {
        guard durationSec > 0, bounds.width > 0 else { return }
        let cx = bounds.width / 2
        let scrollOff = scrollView.contentOffset.x + scrollView.contentInset.left

        let startX = cx + CGFloat(trimStartSec) * pixelsPerSecond - scrollOff - handleW
        let endX   = cx + CGFloat(trimEndSec)   * pixelsPerSecond - scrollOff

        let y = scrollView.frame.minY
        let h = thumbH

        leftHandle.frame  = CGRect(x: startX, y: y, width: handleW, height: h)
        rightHandle.frame = CGRect(x: endX,   y: y, width: handleW, height: h)

        updateTrimBorder()
        updateTrimLabels()
    }

    private func updateTrimBorder() {
        guard bounds.width > 0, durationSec > 0 else { return }
        let x = leftHandle.frame.maxX
        let w = max(0, rightHandle.frame.minX - x)
        let y = scrollView.frame.minY
        let h = thumbH
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let path = UIBezierPath(rect: rect)
        trimBorderLayer.path   = path.cgPath
        trimBorderLayer.frame  = bounds
    }

    private func updateTrimLabels() {
        trimStartLabel.text = formatSec(trimStartSec)
        trimEndLabel.text   = formatSec(trimEndSec)

        // Position just above handles
        let topY = scrollView.frame.minY - 22
        let lx = leftHandle.frame.midX - 22
        let rx = rightHandle.frame.midX - 22
        trimStartLabel.frame = CGRect(x: lx, y: topY, width: 44, height: 18)
        trimEndLabel.frame   = CGRect(x: rx, y: topY, width: 44, height: 18)
    }

    // MARK: Pan Gestures

    @objc private func handleLeftPan(_ gr: UIPanGestureRecognizer) {
        let cx  = bounds.width / 2
        let off = scrollView.contentOffset.x + scrollView.contentInset.left
        let tx  = gr.location(in: self).x

        switch gr.state {
        case .began:
            trimStartLabel.isHidden = false
            delegate?.timelineDidBeginScrubbing(self)
        case .changed:
            let sec = Double((tx - cx + off) / pixelsPerSecond)
            trimStartSec = min(max(0, sec), trimEndSec - 0.2)
            updateTrimHandles()
            delegate?.timeline(self, didChangeTrimStart: CMTime(seconds: trimStartSec,
                                                                preferredTimescale: 600))
        case .ended, .cancelled:
            trimStartLabel.isHidden = true
            delegate?.timelineDidEndScrubbing(self)
        default: break
        }
    }

    @objc private func handleRightPan(_ gr: UIPanGestureRecognizer) {
        let cx  = bounds.width / 2
        let off = scrollView.contentOffset.x + scrollView.contentInset.left
        let tx  = gr.location(in: self).x

        switch gr.state {
        case .began:
            trimEndLabel.isHidden = false
            delegate?.timelineDidBeginScrubbing(self)
        case .changed:
            let sec = Double((tx - cx + off) / pixelsPerSecond)
            trimEndSec = max(min(durationSec, sec), trimStartSec + 0.2)
            updateTrimHandles()
            delegate?.timeline(self, didChangeTrimEnd: CMTime(seconds: trimEndSec,
                                                              preferredTimescale: 600))
        case .ended, .cancelled:
            trimEndLabel.isHidden = true
            delegate?.timelineDidEndScrubbing(self)
        default: break
        }
    }

    // MARK: Thumbnails

    private func generateThumbnails() {
        guard let asset else { return }

        // Clear old
        thumbImageViews.forEach { $0.removeFromSuperview() }
        thumbImageViews = []

        // Create placeholder views immediately
        for i in 0..<thumbCount {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
            if i == 0 { iv.layer.cornerRadius = 6; iv.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner] }
            if i == thumbCount - 1 { iv.layer.cornerRadius = 6; iv.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] }
            thumbStrip.addSubview(iv)
            thumbImageViews.append(iv)
        }

        // Request frames in background
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbW * 2, height: thumbH * 2)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.1, preferredTimescale: 600)

        let step = durationSec / Double(thumbCount)
        var times: [NSValue] = []
        for i in 0..<thumbCount {
            let t = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
            times.append(NSValue(time: t))
        }

        var idx = 0
        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] _, image, _, result, _ in
            guard let self, result == .succeeded, let image else { idx += 1; return }
            let uiImg = UIImage(cgImage: image)
            let capturedIdx = idx
            idx += 1
            DispatchQueue.main.async {
                guard capturedIdx < self.thumbImageViews.count else { return }
                self.thumbImageViews[capturedIdx].image = uiImg
            }
        }
    }

    // MARK: Helpers

    private func formatSec(_ sec: Double) -> String {
        let s = Int(sec)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func clampedTimeSec(_ sec: Double) -> Double {
        guard sec.isFinite else { return 0 }
        return max(0, min(durationSec, sec))
    }

    private func contentOffsetX(for timeSec: Double) -> CGFloat {
        CGFloat(clampedTimeSec(timeSec)) * pixelsPerSecond - scrollView.contentInset.left
    }

    private func centeredTimeSec() -> Double {
        guard durationSec > 0 else { return 0 }
        let rawOffset = scrollView.contentOffset.x + scrollView.contentInset.left
        return clampedTimeSec(Double(rawOffset / pixelsPerSecond))
    }

    private func scrollToTimeSec(_ sec: Double, animated: Bool, notifyDelegate: Bool) {
        guard durationSec > 0 else { return }
        currentTimeSec = clampedTimeSec(sec)
        currentTimeLabel.text = formatSec(currentTimeSec)

        let offset = CGPoint(x: contentOffsetX(for: currentTimeSec), y: 0)
        if notifyDelegate {
            scrollView.setContentOffset(offset, animated: animated)
        } else {
            isSyncingFromPlayer = true
            scrollView.setContentOffset(offset, animated: animated)
            isSyncingFromPlayer = false
            updateTrimHandles()
        }
    }
}

// MARK: - UIScrollViewDelegate

extension ThumbnailTimelineView: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard !isSyncingFromPlayer else { return }
        delegate?.timelineDidBeginScrubbing(self)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { delegate?.timelineDidEndScrubbing(self) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        delegate?.timelineDidEndScrubbing(self)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateTrimHandles()

        guard !isSyncingFromPlayer, durationSec > 0 else { return }
        let clamped = centeredTimeSec()
        currentTimeSec = clamped
        currentTimeLabel.text = formatSec(clamped)

        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        delegate?.timeline(self, didScrollTo: time)
    }
}

// MARK: - Trim Handle View

private enum HandleSide { case left, right }

private final class TrimHandleView: UIView {
    init(side: HandleSide) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 1)
        layer.cornerRadius = 4
        layer.zPosition = 10

        // Notch icon
        let icon = UIImageView(image: UIImage(systemName: side == .left ? "chevron.left" : "chevron.right",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)))
        icon.tintColor = .black
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Floating Label Factory

private func floatingTimeLabel() -> UILabel {
    let l = UILabel()
    l.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    l.textColor = .white
    l.backgroundColor = UIColor(red: 1.0, green: 0.78, blue: 0.0, alpha: 0.9)
    l.textAlignment = .center
    l.layer.cornerRadius = 3
    l.clipsToBounds = true
    return l
}
