
@objc(LKNukeDataModal)
final class NukeDataModal : Modal {
    
    // MARK: Lifecycle
    override func populateContentView() {
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = NSLocalizedString("modal_clear_all_data_title", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("modal_clear_all_data_explanation", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up nuke data button
        let nukeDataButton = UIButton()
        nukeDataButton.set(.height, to: Values.mediumButtonHeight)
        nukeDataButton.layer.cornerRadius = Values.modalButtonCornerRadius
        if isDarkMode {
            nukeDataButton.backgroundColor = Colors.destructive
        }
        nukeDataButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        nukeDataButton.setTitleColor(isLightMode ? Colors.destructive : Colors.text, for: UIControl.State.normal)
        nukeDataButton.setTitle(NSLocalizedString("TXT_DELETE_TITLE", comment: ""), for: UIControl.State.normal)
        nukeDataButton.addTarget(self, action: #selector(nuke), for: UIControl.Event.touchUpInside)
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, nukeDataButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, buttonStackView ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.largeSpacing)
    }
    
    // MARK: Interaction
    @objc private func nuke() {
        func proceed() {
            UserDefaults.removeAll() // Not done in the nuke data implementation as unlinking requires this to happen later
            NotificationCenter.default.post(name: .dataNukeRequested, object: nil)
        }
        if KeyPairUtilities.hasV2KeyPair() {
            proceed()
        } else {
            presentingViewController?.dismiss(animated: true, completion: nil)
            let message = "We’ve upgraded the way Session IDs are generated, so you will be unable to restore your current Session ID."
            let alert = UIAlertController(title: "Are You Sure?", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .destructive) { _ in proceed() })
            alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
            presentingViewController?.present(alert, animated: true, completion: nil)
        }
    }
}
