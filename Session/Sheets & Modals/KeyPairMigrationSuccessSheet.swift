
final class KeyPairMigrationSuccessSheet : Sheet {

    private lazy var sessionIDLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = Fonts.spaceMono(ofSize: isIPhone5OrSmaller ? Values.mediumFontSize : 20)
        result.numberOfLines = 0
        result.lineBreakMode = .byCharWrapping
        return result
    }()
    
    private lazy var copyButton: Button = {
        let result = Button(style: .prominentOutline, size: .large)
        result.set(.width, to: 240)
        result.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copySessionID), for: UIControl.Event.touchUpInside)
        return result
    }()
    
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
        titleLabel.text = "Upgrade Successful!"
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
        explanationLabel.text = "Your new and improved Session ID is:"
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Session ID label
        sessionIDLabel.text = getUserHexEncodedPublicKey()
        // Session ID container
        let sessionIDContainer = UIView()
        sessionIDContainer.addSubview(sessionIDLabel)
        sessionIDLabel.pin(to: sessionIDContainer, withInset: Values.mediumSpacing)
        sessionIDContainer.layer.cornerRadius = TextField.cornerRadius
        sessionIDContainer.layer.borderWidth = 1
        sessionIDContainer.layer.borderColor = Colors.text.cgColor
        // OK button
        let okButton = Button(style: .prominentOutline, size: .large)
        okButton.set(.width, to: 240)
        okButton.setTitle("OK", for: UIControl.State.normal)
        okButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ copyButton, okButton ])
        buttonStackView.axis = .vertical
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.alignment = .center
        // Main stack view
        let stackView = UIStackView(arrangedSubviews: [ topStackView, explanationLabel, sessionIDContainer, buttonStackView ])
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
    
    @objc private func copySessionID() {
        UIPasteboard.general.string = getUserHexEncodedPublicKey()
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("Copied", for: UIControl.State.normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
    
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }
}
