// ExportViewController.swift
// Sheet modal: FPS + quality, live export progress, share-sheet on completion.

import UIKit
import AVFoundation

// MARK: - Delegate

protocol ExportViewControllerDelegate: AnyObject {
    func exportViewController(_ vc: ExportViewController, didRequestExport options: ExportOptions)
}

// MARK: - VC

final class ExportViewController: UIViewController {

    weak var delegate: ExportViewControllerDelegate?

    // MARK: State
    private var selectedFPS: Int = 30
    private var selectedQuality: ExportOptions.Quality = .hd
    private var isExporting = false

    // MARK: – UI

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Export Video"
        l.font = .systemFont(ofSize: 20, weight: .bold)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // ── FPS ──────────────────────────────────────────────────────────────────

    private let fpsHeaderLabel = headerLabel("Frame Rate")

    private lazy var fpsControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["24 fps", "30 fps", "60 fps"])
        sc.selectedSegmentIndex = 1
        configure(segmented: sc)
        sc.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        return sc
    }()

    // ── Quality ───────────────────────────────────────────────────────────────

    private let qualityHeaderLabel = headerLabel("Quality")

    private lazy var qualityControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ExportOptions.Quality.allCases.map(\.rawValue))
        sc.selectedSegmentIndex = 1
        configure(segmented: sc)
        sc.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)
        return sc
    }()

    // ── Progress ──────────────────────────────────────────────────────────────

    private let progressStack: UIStackView = {
        let s = UIStackView()
        s.axis      = .vertical
        s.spacing   = 8
        s.alpha     = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let progressBar: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .default)
        p.progressTintColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
        p.trackTintColor    = UIColor.white.withAlphaComponent(0.15)
        p.layer.cornerRadius = 3
        p.clipsToBounds     = true
        p.translatesAutoresizingMaskIntoConstraints = false
        return p
    }()

    private let progressLabel: UILabel = {
        let l = UILabel()
        l.text          = "Exporting… 0%"
        l.textColor     = UIColor.white.withAlphaComponent(0.7)
        l.font          = .systemFont(ofSize: 13)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // ── Export button ─────────────────────────────────────────────────────────

    private lazy var exportButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Export Now"
        cfg.image = UIImage(systemName: "square.and.arrow.up.fill",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15))
        cfg.imagePadding        = 8
        cfg.baseBackgroundColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle         = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28)
        cfg.titleTextAttributesTransformer = .init { a in
            var b = a; b.font = .systemFont(ofSize: 16, weight: .bold); return b
        }
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.layer.shadowColor   = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1).cgColor
        b.layer.shadowOpacity = 0.45
        b.layer.shadowRadius  = 10
        b.layer.shadowOffset  = CGSize(width: 0, height: 4)
        b.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        return b
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)

        // If presented inside a UINavigationController, configure its bar
        navigationItem.title = ""
        navigationController?.navigationBar.isHidden = true

        setupLayout()
    }

    // MARK: – Layout

    private func setupLayout() {
        progressStack.addArrangedSubview(progressBar)
        progressStack.addArrangedSubview(progressLabel)
        progressBar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let stack = UIStackView(arrangedSubviews: [
            fpsHeaderLabel,
            fpsControl,
            spacer(16),
            qualityHeaderLabel,
            qualityControl,
            spacer(20),
            progressStack
        ])
        stack.axis    = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, stack, exportButton].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([

            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            exportButton.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 28),
            exportButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exportButton.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    // MARK: – Actions

    @objc private func fpsChanged() {
        selectedFPS = [24, 30, 60][fpsControl.selectedSegmentIndex]
    }

    @objc private func qualityChanged() {
        selectedQuality = ExportOptions.Quality.allCases[qualityControl.selectedSegmentIndex]
    }

    @objc private func exportTapped() {
        guard !isExporting else { return }
        isExporting = true
        exportButton.isEnabled = false

        UIView.animate(withDuration: 0.3) { self.progressStack.alpha = 1 }

        let opts = ExportOptions(fps: selectedFPS, quality: selectedQuality)
        delegate?.exportViewController(self, didRequestExport: opts)
    }

    // MARK: – Public progress API (called from EditorViewController)

    func updateProgress(_ value: Float) {
        progressBar.setProgress(value, animated: true)
        progressLabel.text = String(format: "Exporting… %d%%", Int(value * 100))
    }

    func finishExport(with result: Result<URL, Error>) {
        isExporting = false
        exportButton.isEnabled = true

        switch result {
        case .success(let url):
            progressLabel.text = "✅ Done!"
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.completionWithItemsHandler = { [weak self] _, _, _, _ in
                self?.dismiss(animated: true)
            }
            present(share, animated: true)

        case .failure(let err):
            progressLabel.text = "❌ \(err.localizedDescription)"
            progressBar.progressTintColor = .systemRed
        }
    }
}

// MARK: – Helpers

private func headerLabel(_ text: String) -> UILabel {
    let l = UILabel()
    l.text      = text
    l.font      = .systemFont(ofSize: 13, weight: .semibold)
    l.textColor = UIColor.white.withAlphaComponent(0.5)
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}

private func configure(segmented sc: UISegmentedControl) {
    sc.selectedSegmentTintColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
    sc.setTitleTextAttributes([.foregroundColor: UIColor.white,
                                .font: UIFont.systemFont(ofSize: 13, weight: .medium)], for: .selected)
    sc.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.55),
                                .font: UIFont.systemFont(ofSize: 13, weight: .regular)], for: .normal)
    sc.translatesAutoresizingMaskIntoConstraints = false
}

private func spacer(_ h: CGFloat) -> UIView {
    let v = UIView()
    v.heightAnchor.constraint(equalToConstant: h).isActive = true
    return v
}
