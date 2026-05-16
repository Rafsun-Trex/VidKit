// EditingToolsBar.swift
// Horizontal tab bar at the bottom of the editor: Text | Filter | Speed | Blur

import UIKit

enum EditingTool: Int, CaseIterable {
    case text   = 0
    case filter = 1
    case speed  = 2
    case blur   = 3

    var title: String {
        switch self {
        case .text:   return "Text"
        case .filter: return "Filter"
        case .speed:  return "Speed"
        case .blur:   return "Blur"
        }
    }
    var icon: String {
        switch self {
        case .text:   return "textformat"
        case .filter: return "camera.filters"
        case .speed:  return "gauge.with.dots.needle.67percent"
        case .blur:   return "aqi.medium"
        }
    }
}

protocol EditingToolsBarDelegate: AnyObject {
    func editingToolsBar(_ bar: EditingToolsBar, didSelect tool: EditingTool)
}

final class EditingToolsBar: UIView {

    weak var delegate: EditingToolsBarDelegate?

    private var buttons: [UIButton] = []

    private let accent = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        layer.cornerRadius = 16

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for tool in EditingTool.allCases {
            let btn = makeButton(for: tool)
            stack.addArrangedSubview(btn)
            buttons.append(btn)
        }
    }

    private func makeButton(for tool: EditingTool) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: tool.icon,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))
        config.title = tool.title
        config.imagePlacement = .top
        config.imagePadding   = 6
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.55)
        config.titleTextAttributesTransformer = .init { attr in
            var a = attr; a.font = .systemFont(ofSize: 11, weight: .medium); return a
        }
        let b = UIButton(configuration: config)
        b.tag = tool.rawValue
        b.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
        return b
    }

    @objc private func toolTapped(_ sender: UIButton) {
        guard let tool = EditingTool(rawValue: sender.tag) else { return }

        // Highlight active
        buttons.forEach { btn in
            let isActive = btn.tag == sender.tag
            btn.configuration?.baseForegroundColor = isActive
                ? UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
                : UIColor.white.withAlphaComponent(0.55)
        }

        delegate?.editingToolsBar(self, didSelect: tool)
    }
}
