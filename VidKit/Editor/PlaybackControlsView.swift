// PlaybackControlsView.swift
// Compact bar: play/pause button + current / total time display.
// Scrubbing is handled entirely by ThumbnailTimelineView.

import UIKit
import AVFoundation

protocol PlaybackControlsDelegate: AnyObject {
    func playbackControlsDidTapPlayPause(_ view: PlaybackControlsView)
}

final class PlaybackControlsView: UIView {

    weak var delegate: PlaybackControlsDelegate?

    // MARK: Public state

    var isPlaying: Bool = false {
        didSet {
            let cfg = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            let name = isPlaying ? "pause.circle.fill" : "play.circle.fill"
            playPauseButton.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
        }
    }

    var currentTime: CMTime = .zero {
        didSet { currentLabel.text = formatTime(currentTime) }
    }

    var duration: CMTime = .zero {
        didSet { durationLabel.text = formatTime(duration) }
    }

    // MARK: UI

    private let playPauseButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        b.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let currentLabel: UILabel = {
        let l = UILabel()
        l.text = "0:00"
        l.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let separatorLabel: UILabel = {
        let l = UILabel()
        l.text = "/"
        l.font = .systemFont(ofSize: 14, weight: .light)
        l.textColor = UIColor.white.withAlphaComponent(0.4)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let durationLabel: UILabel = {
        let l = UILabel()
        l.text = "0:00"
        l.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        l.textColor = UIColor.white.withAlphaComponent(0.5)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: Init

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = .clear
        playPauseButton.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        let timeStack = UIStackView(arrangedSubviews: [currentLabel, separatorLabel, durationLabel])
        timeStack.axis      = .horizontal
        timeStack.spacing   = 4
        timeStack.alignment = .center
        timeStack.translatesAutoresizingMaskIntoConstraints = false

        [playPauseButton, timeStack].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            playPauseButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 44),
            playPauseButton.heightAnchor.constraint(equalToConstant: 44),

            timeStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @objc private func tapped() { delegate?.playbackControlsDidTapPlayPause(self) }

    private func formatTime(_ time: CMTime) -> String {
        let s = max(0, Int(CMTimeGetSeconds(time)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
