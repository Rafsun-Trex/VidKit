// TextOverlayPanel.swift

import UIKit

protocol TextOverlayPanelDelegate: AnyObject {
    func textOverlayPanel(_ panel: TextOverlayPanel, didUpdate overlays: [TextOverlay])
}

final class TextOverlayPanel: UIView {

    weak var delegate: TextOverlayPanelDelegate?
    private var overlays: [TextOverlay] = [] {
        didSet { delegate?.textOverlayPanel(self, didUpdate: overlays) }
    }

    // MARK: UI

    private lazy var addButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title = "+ Add Text"
        cfg.baseBackgroundColor = UIColor(red: 0.64, green: 0.36, blue: 1.0, alpha: 1)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        cfg.titleTextAttributesTransformer = .init { a in var b = a; b.font = .systemFont(ofSize: 15, weight: .semibold); return b }
        let b = UIButton(configuration: cfg)
        b.addTarget(self, action: #selector(addTextTapped), for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .plain)
        t.backgroundColor = .clear
        t.separatorStyle  = .none
        t.register(TextOverlayCell.self, forCellReuseIdentifier: TextOverlayCell.id)
        t.translatesAutoresizingMaskIntoConstraints = false
        return t
    }()

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate   = self
        addSubview(addButton)
        addSubview(tableView)
        NSLayoutConstraint.activate([
            addButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            addButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            tableView.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func addTextTapped() {
        let overlay = TextOverlay()
        overlays.append(overlay)
        tableView.reloadData()
        // Prompt edit immediately
        presentEditor(for: overlays.count - 1)
    }

    private func presentEditor(for index: Int) {
        guard let vc = findViewController() else { return }
        let alert = UIAlertController(title: "Edit Text", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = self.overlays[index].text
            tf.placeholder = "Enter text…"
        }
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            guard let self else { return }
            if let text = alert.textFields?.first?.text, !text.isEmpty {
                self.overlays[index].text = text
                self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        vc.present(alert, animated: true)
    }
}

// MARK: - UITableView

extension TextOverlayPanel: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        overlays.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TextOverlayCell.id, for: indexPath) as! TextOverlayCell
        cell.configure(with: overlays[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 52 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentEditor(for: indexPath.row)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.overlays.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - Cell

final class TextOverlayCell: UITableViewCell {
    static let id = "TextOverlayCell"

    private let label: UILabel = {
        let l = UILabel()
        l.textColor = .white
        l.font = .systemFont(ofSize: 15)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = UIColor(white: 0.14, alpha: 1)
        layer.cornerRadius = 10
        clipsToBounds = true
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        let sep = UIView()
        sep.backgroundColor = .clear
        selectedBackgroundView = sep
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with overlay: TextOverlay) {
        label.text = overlay.text
        label.textColor = overlay.color
    }
}

// MARK: - Helper

private extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}
