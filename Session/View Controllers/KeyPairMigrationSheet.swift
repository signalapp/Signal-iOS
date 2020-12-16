
final class KeyPairMigrationSheet : Sheet {

    override func populateContentView() {
        // Image view
        let imageView = UIImageView(image: #imageLiteral(resourceName: "Shield").withTint(Colors.text))
        imageView.set(.width, to: 64)
        imageView.set(.height, to: 64)
        imageView.contentMode = .scaleAspectFit
        // Title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = "Session IDs Just Got Better"
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Top stack view
        let topStackView = UIStackView(arrangedSubviews: [ imageView, titleLabel ])
        topStackView.axis = .vertical
        topStackView.spacing = Values.largeSpacing
        topStackView.alignment = .center
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.textAlignment = .center
        explanationLabel.text = """
        We’ve upgraded Session IDs to make them even more private and secure. We recommend upgrading to a new Session ID now.

        You will lose existing contacts and conversations, but you’ll gain even more privacy and security. You will need to upgrade your Session ID eventually, but you can choose to delay the upgrade if you need to save contacts or conversations.
        """
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Upgrade now button
        let upgradeNowButton = Button(style: .prominentOutline, size: .large)
        upgradeNowButton.set(.width, to: 240)
        upgradeNowButton.setTitle("Upgrade Now", for: UIControl.State.normal)
        upgradeNowButton.addTarget(self, action: #selector(upgradeNow), for: UIControl.Event.touchUpInside)
        // Upgrade later button
        let upgradeLaterButton = Button(style: .prominentOutline, size: .large)
        upgradeLaterButton.set(.width, to: 240)
        upgradeLaterButton.setTitle("Upgrade Later", for: UIControl.State.normal)
        upgradeLaterButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ upgradeNowButton, upgradeLaterButton ])
        buttonStackView.axis = .vertical
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.alignment = .center
        // Main stack view
        let stackView = UIStackView(arrangedSubviews: [ topStackView, explanationLabel, buttonStackView ])
        stackView.axis = .vertical
        stackView.spacing = Values.veryLargeSpacing
        stackView.alignment = .center
        // Constraints
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.veryLargeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.veryLargeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.veryLargeSpacing + overshoot)
    }
    
    @objc private func upgradeNow() {
        guard let presentingVC = presentingViewController else { return }
        let message = "You’re upgrading to a new Session ID. This will give you improved privacy and security, but it will clear ALL app data. Contacts and conversations will be lost. Proceed?"
        let alert = UIAlertController(title: "Upgrade Session ID?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes", style: .destructive) { _ in
            Storage.prepareForV2KeyPairMigration()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
        presentingVC.dismiss(animated: true) { // Dismiss self first
            presentingVC.present(alert, animated: true, completion: nil)
        }
    }
}
