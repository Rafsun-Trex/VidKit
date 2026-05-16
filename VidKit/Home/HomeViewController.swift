// HomeViewController.swift
// Landing screen – lets the user pick one or more videos from the library.

import UIKit
import PhotosUI
import AVFoundation

final class HomeViewController: UIViewController {

    // MARK: UI

    private let gradientLayer = CAGradientLayer()

    private let logoLabel: UILabel = {
        let l = UILabel()
        l.text = "✂️ VidKit"
        l.font = .systemFont(ofSize: 34, weight: .black)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.text = "Edit videos with ease"
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.textColor = UIColor.white.withAlphaComponent(0.6)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var addButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Add Video"
        config.image = UIImage(systemName: "plus.circle.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))
        config.imagePadding = 10
        config.baseBackgroundColor = UIColor.white
        config.baseForegroundColor = UIColor(red: 0.36, green: 0.14, blue: 0.82, alpha: 1)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28,
                                                       bottom: 16, trailing: 28)
        config.titleTextAttributesTransformer = .init { attr in
            var a = attr; a.font = .systemFont(ofSize: 18, weight: .bold); return a
        }
        let b = UIButton(configuration: config)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(addVideoTapped), for: .touchUpInside)
        return b
    }()

    private let recentLabel: UILabel = {
        let l = UILabel()
        l.text = "Recent Projects"
        l.font = .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let emptyStateView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "film.stack"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.3)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        let lbl = UILabel()
        lbl.text = "No projects yet.\nTap 'Add Video' to start."
        lbl.numberOfLines = 0
        lbl.textAlignment = .center
        lbl.textColor = UIColor.white.withAlphaComponent(0.3)
        lbl.font = .systemFont(ofSize: 14)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [icon, lbl])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.heightAnchor.constraint(equalToConstant: 60),
            icon.widthAnchor.constraint(equalToConstant: 60),
            stack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        return v
    }()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGradient()
        setupLayout()
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    // MARK: Setup

    private func setupGradient() {
        gradientLayer.colors = [
            UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1).cgColor,
            UIColor(red: 0.14, green: 0.06, blue: 0.28, alpha: 1).cgColor
        ]
        gradientLayer.locations = [0, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint   = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)
    }

    private func setupLayout() {
        [logoLabel, subtitleLabel, addButton, recentLabel, emptyStateView].forEach {
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            logoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
            logoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            addButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 44),
            addButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            addButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            recentLabel.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 52),
            recentLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            emptyStateView.topAnchor.constraint(equalTo: recentLabel.bottomAnchor, constant: 16),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: Actions

    @objc private func addVideoTapped() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension HomeViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }

        result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
            guard let url, error == nil else { return }
            // Copy to app's tmp so we own the file lifecycle
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)

            DispatchQueue.main.async {
                let state = EditState()
                state.assetURL  = dest
                state.trimEnd   = AVURLAsset(url: dest).duration
                let editor = EditorViewController(editState: state)
                self?.navigationController?.pushViewController(editor, animated: true)
            }
        }
    }
}
