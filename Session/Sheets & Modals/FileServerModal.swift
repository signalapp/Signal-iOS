
final class FileServerModal : Modal {

    override func populateContentView() {
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = "Session"
        titleLabel.textAlignment = .center
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = "We're upgrading the way files are stored. File transfer may be unstable for the next 24-48 hours."
        messageLabel.text = message
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        // OK button
        let okButton = UIButton()
        okButton.set(.height, to: Values.mediumButtonHeight)
        okButton.layer.cornerRadius = Modal.buttonCornerRadius
        okButton.backgroundColor = Colors.buttonBackground
        okButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        okButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        okButton.setTitle("OK", for: UIControl.State.normal)
        okButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ okButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.largeSpacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }
}
