// EditorViewController.swift
// Full editor: nav bar (back + export), video player, thumbnail timeline,
// play controls, collapsible tool panels, floating export button.

import UIKit
import AVFoundation

final class EditorViewController: UIViewController {

    // MARK: Dependencies
    let editState: EditState
    private let compositionService = VideoCompositionService()

    // MARK: AVPlayer
    private var player:       AVPlayer?
    private var playerItem:   AVPlayerItem?
    private var timeObserver: Any?
    private var isScrubbing = false

    // MARK: UI – fixed layout components
    private let playerView       = VideoPlayerView()
    private let timeline         = ThumbnailTimelineView()
    private let playbackControls = PlaybackControlsView()
    private let toolsBar         = EditingToolsBar()
    private let exportBtn        = ExportButtonView()

    // MARK: Panels (lazy)
    private lazy var textPanel:   TextOverlayPanel = { let p = TextOverlayPanel();  p.delegate = self; return p }()
    private lazy var filterPanel: FilterPanel      = { let p = FilterPanel();       p.delegate = self; return p }()
    private lazy var speedPanel:  SpeedPanel       = { let p = SpeedPanel();        p.delegate = self; return p }()
    private lazy var blurPanel:   BlurPanel        = { let p = BlurPanel();         p.delegate = self; return p }()

    private var activePanelView: UIView?
    private let panelContainer = UIView()
    private var playerViewHeight: NSLayoutConstraint!
    private var panelContainerHeight: NSLayoutConstraint!

    // MARK: Init
    init(editState: EditState) {
        self.editState = editState
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1)
        setupNavBar()
        setupLayout()
        wireup()
        loadVideo()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Always show the nav bar in the editor (home hides it)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
        removeTimeObserver()
        // Hide nav bar again when popping back to Home
        if isMovingFromParent {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    // MARK: – Navigation Bar

    private func setupNavBar() {
        title = "Editor"

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigationItem.standardAppearance   = appearance
        navigationItem.scrollEdgeAppearance = appearance

        // Back button – custom chevron, purple tint
        let backImg = UIImage(systemName: "chevron.left",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        navigationController?.navigationBar.backIndicatorImage                 = backImg
        navigationController?.navigationBar.backIndicatorTransitionMaskImage   = backImg
        navigationItem.backButtonTitle = ""
        navigationController?.navigationBar.tintColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
    }

    // MARK: – Layout

    private func setupLayout() {
        [playerView, timeline, playbackControls,
         panelContainer, toolsBar, exportBtn].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        panelContainer.backgroundColor = UIColor(white: 0.10, alpha: 1)
        panelContainer.layer.cornerRadius = 16
        panelContainer.clipsToBounds = true

        playerViewHeight = playerView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.42)
        panelContainerHeight = panelContainer.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([

            // ── Player ──────────────────────────────────────────────
            playerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            playerViewHeight,

            // ── Timeline ────────────────────────────────────────────
            timeline.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 10),
            timeline.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            timeline.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            timeline.heightAnchor.constraint(equalToConstant: 92),   // thumbs + handle room

            // ── Playback Controls ───────────────────────────────────
            playbackControls.topAnchor.constraint(equalTo: timeline.bottomAnchor, constant: 4),
            playbackControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playbackControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playbackControls.heightAnchor.constraint(equalToConstant: 48),

            // ── Panel (collapsible) ──────────────────────────────────
            panelContainer.topAnchor.constraint(equalTo: playbackControls.bottomAnchor, constant: 8),
            panelContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            panelContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            panelContainerHeight,

            // ── Tool tabs ───────────────────────────────────────────
            toolsBar.topAnchor.constraint(equalTo: panelContainer.bottomAnchor, constant: 8),
            toolsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toolsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            toolsBar.heightAnchor.constraint(equalToConstant: 68),

            // ── Export button (trailing, below tool bar) ─────────────
            exportBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            exportBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: – Wireup

    private func wireup() {
        timeline.delegate         = self
        playbackControls.delegate = self
        toolsBar.delegate         = self
        exportBtn.onTap           = { [weak self] in self?.presentExport() }
    }

    // MARK: – Video Loading

    private func loadVideo() {
        guard let asset = editState.asset else { return }
        Task {
            let duration = (try? await asset.load(.duration)) ?? .zero
            await MainActor.run {
                editState.trimEnd = duration
                playbackControls.duration = duration
                timeline.configure(asset: asset, duration: duration)
                timeline.setTrimStart(editState.trimStart)
                timeline.setTrimEnd(editState.trimEnd)
                buildComposition()
            }
        }
    }

    private func buildComposition(preservingSourceTime sourceTimeToRestore: CMTime? = nil) {
        let sourceTimeToRestore = sourceTimeToRestore ?? currentSourceTimeForPreview()
        guard let (comp, videoComp) = compositionService.build(from: editState) else { return }
        let restoreTime = clampedRestoreTime(compositionTime(forSourceTime: sourceTimeToRestore), duration: comp.duration)
        let shouldResume = player?.timeControlStatus == .playing

        let item = AVPlayerItem(asset: comp)
        item.videoComposition = videoComp

        if let p = player {
            p.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
            playerView.player = player
        }
        playerItem = item
        setupTimeObserver()
        playbackControls.duration = comp.duration
        restorePreviewPlayback(to: restoreTime, resume: shouldResume, item: item)

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(playerReachedEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: item)
    }

    private func clampedRestoreTime(_ time: CMTime?, duration: CMTime) -> CMTime {
        guard let time, time.isValid, duration.isValid, duration > .zero else { return .zero }
        if time < .zero { return .zero }
        if time > duration { return duration }
        return time
    }

    private func restorePreviewPlayback(to time: CMTime, resume: Bool, item: AVPlayerItem) {
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self, self.playerItem === item, resume else { return }
            self.player?.play()
            self.playbackControls.isPlaying = true
        }
        playbackControls.currentTime = time
        timeline.setCurrentTime(sourceTime(forCompositionTime: time), animated: false)
        playerView.updateTextVisibility(currentTime: time)
    }

    // MARK: – Time Observer

    private func setupTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.04, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            self.playbackControls.currentTime = time
            self.timeline.setCurrentTime(self.sourceTime(forCompositionTime: time), animated: false)
            self.playerView.updateTextVisibility(currentTime: time)
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
    }

    @objc private func playerReachedEnd() {
        player?.seek(to: .zero)
        player?.play()
    }

    // MARK: – Timeline / Composition Time Mapping

    private func currentSourceTimeForPreview() -> CMTime {
        guard let player else { return editState.trimStart }
        return sourceTime(forCompositionTime: player.currentTime())
    }

    private func sourceTime(forCompositionTime time: CMTime) -> CMTime {
        let startSec = seconds(from: editState.trimStart)
        let compSec = max(0, seconds(from: time))
        let sourceSec = startSec + compSec * Double(max(editState.speed, 0.001))
        return CMTime(seconds: clampedSourceSeconds(sourceSec), preferredTimescale: 600)
    }

    private func compositionTime(forSourceTime time: CMTime) -> CMTime {
        let startSec = seconds(from: editState.trimStart)
        let sourceSec = clampedSourceSeconds(seconds(from: time, fallback: startSec))
        let speed = Double(max(editState.speed, 0.001))
        let compSec = max(0, (sourceSec - startSec) / speed)
        return CMTime(seconds: compSec, preferredTimescale: 600)
    }

    private func clampedSourceSeconds(_ sec: Double) -> Double {
        let startSec = seconds(from: editState.trimStart)
        let endSec = max(startSec, activeTrimEndSeconds())
        return max(startSec, min(endSec, sec))
    }

    private func activeTrimEndSeconds() -> Double {
        if CMTIME_IS_INDEFINITE(editState.trimEnd) {
            return seconds(from: editState.asset?.duration ?? .zero)
        }
        return seconds(from: editState.trimEnd)
    }

    private func seconds(from time: CMTime, fallback: Double = 0) -> Double {
        let value = CMTimeGetSeconds(time)
        return value.isFinite ? value : fallback
    }

    // MARK: – Panel Management

    private func showPanel(_ panel: UIView, height: CGFloat) {
        guard activePanelView !== panel else { hidePanel(); return }
        activePanelView?.removeFromSuperview()
        activePanelView = panel

        panel.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: panelContainer.topAnchor),
            panel.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor)
        ])
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4) {
            self.panelContainerHeight.constant = height
            self.view.layoutIfNeeded()
        }
    }

    private func hidePanel() {
        UIView.animate(withDuration: 0.22) {
            self.panelContainerHeight.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.activePanelView?.removeFromSuperview()
            self.activePanelView = nil
        }
    }

    private func rebuildComposition() {
        buildComposition()
        playerView.syncTextOverlays(editState.textOverlays)
    }

    private func rebuildComposition(preservingSourceTime sourceTime: CMTime) {
        buildComposition(preservingSourceTime: sourceTime)
        playerView.syncTextOverlays(editState.textOverlays)
    }

    // MARK: – Export

    private func presentExport() {
        player?.pause()
        playbackControls.isPlaying = false

        let vc = ExportViewController()
        vc.delegate = self
        let sheet = UINavigationController(rootViewController: vc)
        if let presenter = sheet.sheetPresentationController {
            presenter.detents = [.medium()]
            presenter.prefersGrabberVisible = true
            presenter.preferredCornerRadius = 24
        }
        present(sheet, animated: true)
    }
}

// MARK: – ThumbnailTimelineDelegate

extension EditorViewController: ThumbnailTimelineDelegate {
    func timeline(_ view: ThumbnailTimelineView, didScrollTo time: CMTime) {
        let compositionTime = compositionTime(forSourceTime: time)
        player?.seek(to: compositionTime, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackControls.currentTime = compositionTime
        playerView.updateTextVisibility(currentTime: compositionTime)
    }

    func timeline(_ view: ThumbnailTimelineView, didChangeTrimStart time: CMTime) {
        let sourceTime = currentSourceTimeForPreview()
        editState.trimStart = time
        rebuildComposition(preservingSourceTime: sourceTime)
    }

    func timeline(_ view: ThumbnailTimelineView, didChangeTrimEnd time: CMTime) {
        let sourceTime = currentSourceTimeForPreview()
        editState.trimEnd = time
        rebuildComposition(preservingSourceTime: sourceTime)
    }

    func timelineDidBeginScrubbing(_ view: ThumbnailTimelineView) {
        isScrubbing = true
        player?.pause()
        playbackControls.isPlaying = false
    }

    func timelineDidEndScrubbing(_ view: ThumbnailTimelineView) {
        isScrubbing = false
    }
}

// MARK: – PlaybackControlsDelegate

extension EditorViewController: PlaybackControlsDelegate {
    func playbackControlsDidTapPlayPause(_ view: PlaybackControlsView) {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            playbackControls.isPlaying = false
        } else {
            player.play()
            playbackControls.isPlaying = true
        }
    }
}

// MARK: – EditingToolsBarDelegate

extension EditorViewController: EditingToolsBarDelegate {
    func editingToolsBar(_ bar: EditingToolsBar, didSelect tool: EditingTool) {
        switch tool {
        case .text:   showPanel(textPanel,   height: 190)
        case .filter: showPanel(filterPanel, height: 130)
        case .speed:  showPanel(speedPanel,  height: 165)
        case .blur:   showPanel(blurPanel,   height: 155)
        }
    }
}

// MARK: – TextOverlayPanelDelegate

extension EditorViewController: TextOverlayPanelDelegate {
    func textOverlayPanel(_ panel: TextOverlayPanel, didUpdate overlays: [TextOverlay]) {
        editState.textOverlays = overlays
        playerView.syncTextOverlays(overlays)
        rebuildComposition()
    }
}

// MARK: – FilterPanelDelegate

extension EditorViewController: FilterPanelDelegate {
    func filterPanel(_ panel: FilterPanel, didSelect filter: VideoFilter) {
        editState.filter = filter
        rebuildComposition()
    }
}

// MARK: – SpeedPanelDelegate

extension EditorViewController: SpeedPanelDelegate {
    func speedPanel(_ panel: SpeedPanel, didChangeSpeed speed: Float) {
        let sourceTime = currentSourceTimeForPreview()
        editState.speed = speed
        rebuildComposition(preservingSourceTime: sourceTime)
    }
}

// MARK: – BlurPanelDelegate

extension EditorViewController: BlurPanelDelegate {
    func blurPanel(_ panel: BlurPanel, didChangeType type: BlurType) {
        editState.blurType = type
        rebuildComposition()
    }
    func blurPanel(_ panel: BlurPanel, didChangeIntensity intensity: Float) {
        editState.blurIntensity = intensity
        rebuildComposition()
    }
}

// MARK: – ExportViewControllerDelegate

extension EditorViewController: ExportViewControllerDelegate {
    func exportViewController(_ vc: ExportViewController,
                               didRequestExport options: ExportOptions) {
        compositionService.export(state: editState, options: options,
                                   progress: { p in DispatchQueue.main.async { vc.updateProgress(p) } },
                                   completion: { r in DispatchQueue.main.async { vc.finishExport(with: r) } })
    }
}
