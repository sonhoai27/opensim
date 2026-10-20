import UIKit

final class FixtureViewController: UIViewController {
    private var tapCount = 0

    private let titleLabel = UILabel()
    private let textField = UITextField()
    private let textValueLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private let toggle = UISwitch()
    private let toggleStateLabel = UILabel()
    private let slider = UISlider()
    private let sliderValueLabel = UILabel()
    private let detailsButton = UIButton(type: .system)
    private let gestureLabel = UILabel()
    private let canvasLabel = UILabel()
    private let selectionLabel = UILabel()
    private let bottomLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "fixture-root"
        configureNavigation()
        configureLayout()
    }

    private func configureNavigation() {
        title = "Fixture"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Details",
            style: .plain,
            target: self,
            action: #selector(detailsTapped)
        )
    }

    private func configureLayout() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        titleLabel.text = "OpenSim Fixture"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.accessibilityIdentifier = "fixture-title"
        stack.addArrangedSubview(titleLabel)

        textField.placeholder = "Type here"
        textField.borderStyle = .roundedRect
        textField.accessibilityIdentifier = "fixture-text-field"
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        textField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(textField)

        textValueLabel.accessibilityIdentifier = "fixture-text-value"
        textValueLabel.text = "text="
        textValueLabel.numberOfLines = 0
        stack.addArrangedSubview(textValueLabel)

        primaryButton.setTitle("Primary Action", for: .normal)
        primaryButton.accessibilityIdentifier = "fixture-primary-button"
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primaryButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(primaryButton)

        counterLabel.accessibilityIdentifier = "fixture-counter-label"
        counterLabel.text = "0"
        stack.addArrangedSubview(counterLabel)

        toggle.accessibilityIdentifier = "fixture-toggle"
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        stack.addArrangedSubview(toggle)

        toggleStateLabel.accessibilityIdentifier = "fixture-toggle-state"
        toggleStateLabel.text = "off"
        stack.addArrangedSubview(toggleStateLabel)

        slider.accessibilityIdentifier = "fixture-slider"
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.value = 50
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        stack.addArrangedSubview(slider)

        sliderValueLabel.accessibilityIdentifier = "fixture-slider-value"
        sliderValueLabel.text = "50"
        stack.addArrangedSubview(sliderValueLabel)

        detailsButton.setTitle("Open Details", for: .normal)
        detailsButton.accessibilityIdentifier = "fixture-details-button"
        detailsButton.addTarget(self, action: #selector(detailsTapped), for: .touchUpInside)
        detailsButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(detailsButton)

        let longPressTarget = makeGestureContainer(
            identifier: "fixture-long-press-target",
            label: "Long press target",
            height: 88
        )
        longPressTarget.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed)))
        stack.addArrangedSubview(longPressTarget)

        let swipeArea = makeGestureContainer(
            identifier: "fixture-swipe-area",
            label: "Swipe area",
            height: 88
        )
        swipeArea.addGestureRecognizer(UISwipeGestureRecognizer(target: self, action: #selector(swipedLeft)))
        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(swipedRight))
        rightSwipe.direction = .right
        swipeArea.addGestureRecognizer(rightSwipe)
        stack.addArrangedSubview(swipeArea)

        let canvas = makeGestureContainer(
            identifier: "fixture-gesture-canvas",
            label: "Pinch and rotate canvas",
            height: 140
        )
        canvas.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched)))
        canvas.addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(rotated)))
        stack.addArrangedSubview(canvas)

        gestureLabel.accessibilityIdentifier = "fixture-gesture-label"
        gestureLabel.text = "gesture="
        stack.addArrangedSubview(gestureLabel)

        canvasLabel.accessibilityIdentifier = "fixture-canvas-label"
        canvasLabel.text = "canvas="
        stack.addArrangedSubview(canvasLabel)

        for item in ["Alpha", "Beta", "Gamma"] {
            let identifier = "fixture-item-\(item.lowercased())"
            let button = makeButton(item, identifier: identifier, action: #selector(itemTapped(_:)))
            stack.addArrangedSubview(button)
        }

        selectionLabel.accessibilityIdentifier = "fixture-selection-label"
        selectionLabel.text = "selection="
        stack.addArrangedSubview(selectionLabel)

        for _ in 0..<12 {
            let spacer = UIView()
            spacer.backgroundColor = .clear
            spacer.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(spacer)
        }

        bottomLabel.text = "Bottom of fixture"
        bottomLabel.accessibilityIdentifier = "fixture-bottom-label"
        bottomLabel.textAlignment = .center
        stack.addArrangedSubview(bottomLabel)
    }

    private func makeButton(_ title: String, identifier: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    private func makeGestureContainer(identifier: String, label: String, height: CGFloat) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 12
        container.isAccessibilityElement = true
        container.accessibilityIdentifier = identifier
        container.accessibilityLabel = label
        container.heightAnchor.constraint(equalToConstant: height).isActive = true

        let inner = UILabel()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.text = label
        inner.isUserInteractionEnabled = false
        inner.textAlignment = .center
        inner.textColor = .secondaryLabel
        container.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            inner.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
            inner.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
        ])
        return container
    }

    @objc private func primaryTapped() {
        tapCount += 1
        counterLabel.text = "\(tapCount)"
        primaryButton.setTitle("Primary Action \(tapCount)", for: .normal)
    }

    @objc private func textChanged() {
        textValueLabel.text = "text=\(textField.text ?? "")"
    }

    @objc private func toggleChanged() {
        toggleStateLabel.text = toggle.isOn ? "on" : "off"
    }

    @objc private func sliderChanged() {
        sliderValueLabel.text = String(format: "%.0f", slider.value)
    }

    @objc private func detailsTapped() {
        navigationController?.pushViewController(DetailsViewController(), animated: true)
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            gestureLabel.text = "gesture=long-press"
        }
    }

    @objc private func swipedLeft(_ gesture: UISwipeGestureRecognizer) {
        gestureLabel.text = "gesture=swipe-left"
    }

    @objc private func swipedRight(_ gesture: UISwipeGestureRecognizer) {
        gestureLabel.text = "gesture=swipe-right"
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        canvasLabel.text = String(format: "canvas=scale:%.2f,rotation:%.2f", gesture.scale, 1.0)
    }

    @objc private func rotated(_ gesture: UIRotationGestureRecognizer) {
        canvasLabel.text = String(format: "canvas=scale:%.2f,rotation:%.2f", 1.0, gesture.rotation)
    }

    @objc private func itemTapped(_ sender: UIButton) {
        selectionLabel.text = "selection=\(sender.title(for: .normal) ?? "")"
    }
}
