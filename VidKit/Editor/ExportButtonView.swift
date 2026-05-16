// ExportButtonView.swift
// A prominent floating "Export" pill button, always visible in the editor.

import UIKit

final class ExportButtonView: UIView {

    var onTap: (() -> Void)?

    private lazy var button: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title            = "Export"
        cfg.image            = UIImage(systemName: "square.and.arrow.up",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        cfg.imagePlacement   = .leading
        cfg.imagePadding     = 6
        cfg.baseBackgroundColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle         = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        cfg.titleTextAttributesTransformer = .init { a in
            var b = a; b.font = .systemFont(ofSize: 15, weight: .bold); return b
        }
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        // Shadow
        b.layer.shadowColor   = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1).cgColor
        b.layer.shadowOpacity = 0.55
        b.layer.shadowRadius  = 10
        b.layer.shadowOffset  = CGSize(width: 0, height: 4)
        return b
    }()

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = .clear
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc private func tapped() { onTap?() }
}
