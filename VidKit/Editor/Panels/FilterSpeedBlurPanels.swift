// FilterPanel.swift

import UIKit

protocol FilterPanelDelegate: AnyObject {
    func filterPanel(_ panel: FilterPanel, didSelect filter: VideoFilter)
}

final class FilterPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    weak var delegate: FilterPanelDelegate?
    private var selectedFilter: VideoFilter = .none

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 72, height: 88)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.dataSource = self
        cv.delegate   = self
        cv.register(FilterCell.self, forCellWithReuseIdentifier: FilterCell.id)
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 100)
        ])
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        VideoFilter.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FilterCell.id, for: indexPath) as! FilterCell
        let filter = VideoFilter.allCases[indexPath.item]
        cell.configure(with: filter, selected: filter == selectedFilter)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let filter = VideoFilter.allCases[indexPath.item]
        selectedFilter = filter
        collectionView.reloadData()
        delegate?.filterPanel(self, didSelect: filter)
    }
}

private final class FilterCell: UICollectionViewCell {
    static let id = "FilterCell"

    private let iconView = UIImageView()
    private let label    = UILabel()
    private let ring     = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor   = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        ring.layer.cornerRadius = 30
        ring.layer.borderWidth  = 2
        ring.layer.borderColor  = UIColor.clear.cgColor
        ring.backgroundColor    = UIColor(white: 0.18, alpha: 1)
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.addSubview(iconView)

        contentView.addSubview(ring)
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            ring.topAnchor.constraint(equalTo: contentView.topAnchor),
            ring.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            ring.widthAnchor.constraint(equalToConstant: 60),
            ring.heightAnchor.constraint(equalToConstant: 60),
            iconView.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            label.topAnchor.constraint(equalTo: ring.bottomAnchor, constant: 6),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with filter: VideoFilter, selected: Bool) {
        iconView.image = UIImage(systemName: filter.icon)
        label.text     = filter.rawValue
        ring.layer.borderColor = selected
            ? UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1).cgColor
            : UIColor.clear.cgColor
        ring.backgroundColor = selected
            ? UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 0.25)
            : UIColor(white: 0.18, alpha: 1)
    }
}


// ──────────────────────────────────────────────────────────────────────────────
// MARK: - SpeedPanel
// ──────────────────────────────────────────────────────────────────────────────

protocol SpeedPanelDelegate: AnyObject {
    func speedPanel(_ panel: SpeedPanel, didChangeSpeed speed: Float)
}

final class SpeedPanel: UIView {

    weak var delegate: SpeedPanelDelegate?

    private let presets: [Float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]

    private let slider: UISlider = {
        let s = UISlider()
        s.minimumValue = 0.25
        s.maximumValue = 4.0
        s.value        = 1.0
        s.minimumTrackTintColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
        s.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        s.thumbTintColor = .white
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let valueLabel: UILabel = {
        let l = UILabel()
        l.text = "1.0×"
        l.textColor = .white
        l.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var presetButtons: [UIButton] = []

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        for speed in presets {
            var cfg = UIButton.Configuration.tinted()
            cfg.title = speed == 1.0 ? "1×" : (speed < 1 ? "\(speed)×" : "\(Int(speed))×")
            cfg.baseForegroundColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
            cfg.baseBackgroundColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
            cfg.cornerStyle = .capsule
            cfg.contentInsets = .init(top: 6, leading: 4, bottom: 6, trailing: 4)
            cfg.titleTextAttributesTransformer = .init { a in var b = a; b.font = .systemFont(ofSize: 13, weight: .bold); return b }
            let b = UIButton(configuration: cfg)
            b.tag = Int(speed * 100)
            b.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            presetButtons.append(b)
            stack.addArrangedSubview(b)
        }

        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        [valueLabel, stack, slider].forEach { addSubview($0) }
        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            slider.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 18),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        ])
    }

    @objc private func sliderChanged() {
        let v = slider.value
        valueLabel.text = String(format: "%.2f×", v)
        delegate?.speedPanel(self, didChangeSpeed: v)
    }

    @objc private func presetTapped(_ sender: UIButton) {
        let speed = Float(sender.tag) / 100
        slider.setValue(speed, animated: true)
        valueLabel.text = String(format: "%.2f×", speed)
        delegate?.speedPanel(self, didChangeSpeed: speed)
    }
}


// ──────────────────────────────────────────────────────────────────────────────
// MARK: - BlurPanel
// ──────────────────────────────────────────────────────────────────────────────

protocol BlurPanelDelegate: AnyObject {
    func blurPanel(_ panel: BlurPanel, didChangeType type: BlurType)
    func blurPanel(_ panel: BlurPanel, didChangeIntensity intensity: Float)
}

final class BlurPanel: UIView {

    weak var delegate: BlurPanelDelegate?

    private let typeButtons: [BlurType: UIButton] = {
        var d: [BlurType: UIButton] = [:]
        for t in BlurType.allCases {
            var cfg = UIButton.Configuration.tinted()
            cfg.title = t.rawValue
            cfg.image = UIImage(systemName: t.icon,
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
            cfg.imagePadding = 6
            cfg.baseForegroundColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
            cfg.baseBackgroundColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
            cfg.cornerStyle = .capsule
            cfg.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
            cfg.titleTextAttributesTransformer = .init { a in var b = a; b.font = .systemFont(ofSize: 13, weight: .medium); return b }
            d[t] = UIButton(configuration: cfg)
        }
        return d
    }()

    private let intensitySlider: UISlider = {
        let s = UISlider()
        s.minimumValue = 1
        s.maximumValue = 25
        s.value        = 8
        s.minimumTrackTintColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
        s.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        s.thumbTintColor = .white
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let intensityLabel: UILabel = {
        let l = UILabel()
        l.text = "Intensity"
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.spacing = 10
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        for type in BlurType.allCases {
            guard let btn = typeButtons[type] else { continue }
            btn.tag = type.rawValue.hashValue  // use hashValue as tag isn't great but fine here
            // Use accessibility id instead
            btn.accessibilityIdentifier = type.rawValue
            btn.addTarget(self, action: #selector(typeTapped(_:)), for: .touchUpInside)
            buttonStack.addArrangedSubview(btn)
        }

        intensitySlider.addTarget(self, action: #selector(intensityChanged), for: .valueChanged)

        [buttonStack, intensityLabel, intensitySlider].forEach { addSubview($0) }
        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            buttonStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            intensityLabel.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 18),
            intensityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            intensitySlider.topAnchor.constraint(equalTo: intensityLabel.bottomAnchor, constant: 8),
            intensitySlider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            intensitySlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        ])
    }

    @objc private func typeTapped(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier,
              let type = BlurType.allCases.first(where: { $0.rawValue == id }) else { return }
        delegate?.blurPanel(self, didChangeType: type)
    }

    @objc private func intensityChanged() {
        delegate?.blurPanel(self, didChangeIntensity: intensitySlider.value)
    }
}
