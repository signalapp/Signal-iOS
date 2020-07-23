
final class OpenGroupSuggestionSheet : Sheet {

    override func populateContentView() {
        // Set up image view
        let imageView = UIImageView(image: #imageLiteral(resourceName: "ChatBubbles"))
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = NSLocalizedString("No messages yet", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        // Set up top explanation label
        let topExplanationLabel = UILabel()
        topExplanationLabel.textColor = Colors.text
        topExplanationLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        topExplanationLabel.text = NSLocalizedString("Would you like to join the Session Public Chat?", comment: "")
        topExplanationLabel.numberOfLines = 0
        topExplanationLabel.textAlignment = .center
        topExplanationLabel.lineBreakMode = .byWordWrapping
        // Set up join button
        let joinButton = Button(style: .prominentOutline, size: .medium)
        joinButton.set(.width, to: 240)
        joinButton.setTitle(NSLocalizedString("Join Public Chat", comment: ""), for: UIControl.State.normal)
        joinButton.addTarget(self, action: #selector(joinSessionPublicChat), for: UIControl.Event.touchUpInside)
        // Set up dismiss button
        let dismissButton = Button(style: .regular, size: .medium)
        dismissButton.set(.width, to: 240)
        dismissButton.setTitle(NSLocalizedString("No, thank you", comment: ""), for: UIControl.State.normal)
        dismissButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        // Set up bottom explanation label
        let bottomExplanationLabel = UILabel()
        bottomExplanationLabel.textColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        bottomExplanationLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        bottomExplanationLabel.text = NSLocalizedString("Open groups can be joined by anyone and do not provide full privacy protection", comment: "")
        bottomExplanationLabel.numberOfLines = 0
        bottomExplanationLabel.textAlignment = .center
        bottomExplanationLabel.lineBreakMode = .byWordWrapping
        // Set up button stack view
        let bottomStackView = UIStackView(arrangedSubviews: [ joinButton, dismissButton, bottomExplanationLabel ])
        bottomStackView.axis = .vertical
        bottomStackView.spacing = Values.mediumSpacing
        bottomStackView.alignment = .fill
        // Set up main stack view
        let stackView = UIStackView(arrangedSubviews: [ imageView, titleLabel, topExplanationLabel, bottomStackView ])
        stackView.axis = .vertical
        stackView.spacing = Values.largeSpacing
        stackView.alignment = .center
        // Set up constraints
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.veryLargeSpacing + overshoot)
    }

    @objc private func joinSessionPublicChat() {
        // TODO: Duplicate of the code in JoinPublicChatVC
        let channelID: UInt64 = 1
        let url = "https://chat.getsession.org"
        let displayName = OWSProfileManager.shared().localProfileName()
        // TODO: Profile picture & profile key
        let _ = PublicChatManager.shared.addChat(server: url, channel: channelID).done(on: .main) { _ in
            let _ = PublicChatAPI.getMessages(for: channelID, on: url)
            let _ = PublicChatAPI.setDisplayName(to: displayName, on: url)
            let _ = PublicChatAPI.join(channelID, on: url)
        }
        close()
    }

    override func close() {
        UserDefaults.standard[.hasSeenOpenGroupSuggestionSheet] = true
        super.close()
    }
}
