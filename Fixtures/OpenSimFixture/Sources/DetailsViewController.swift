import UIKit

final class DetailsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Details"
        view.accessibilityIdentifier = "fixture-details-view"

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Fixture details"
        label.accessibilityIdentifier = "fixture-details-label"
        label.textAlignment = .center
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
