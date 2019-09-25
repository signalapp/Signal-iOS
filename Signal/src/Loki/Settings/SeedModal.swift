import NVActivityIndicatorView

@objc(LKSeedModal)
final class SeedModal : Modal {
    
    private let mnemonic: String = {
        let identityManager = OWSIdentityManager.shared()
        let databaseConnection = identityManager.value(forKey: "dbConnection") as! YapDatabaseConnection
        var hexEncodedSeed: String! = databaseConnection.object(forKey: "LKLokiSeed", inCollection: OWSPrimaryStorageIdentityKeyStoreCollection) as! String?
        if hexEncodedSeed == nil {
            hexEncodedSeed = identityManager.identityKeyPair()!.hexEncodedPrivateKey // Legacy account
        }
        return Mnemonic.encode(hexEncodedString: hexEncodedSeed)
    }()
    
    // MARK: Lifecycle
    override func populateContentView() {
        // Label
        let titleLabel = UILabel()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeHeadlineClamped
        titleLabel.text = NSLocalizedString("Your Seed", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        // Subtitle label
        let subtitleLabel = UILabel()
        subtitleLabel.textColor = Theme.primaryColor
        subtitleLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        subtitleLabel.text = NSLocalizedString("This is your personal secret. It can be used to restore your account if you lose access, or to migrate to a new device.", comment: "")
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.textAlignment = .center
        // Mnemonic label
        let mnemonicLabel = UILabel()
        let font = UIFont.ows_dynamicTypeCaption1Clamped
        mnemonicLabel.font = UIFont(descriptor: font.fontDescriptor.withSymbolicTraits(.traitItalic)!, size: font.pointSize)
        mnemonicLabel.text = mnemonic
        mnemonicLabel.numberOfLines = 0
        mnemonicLabel.textAlignment = .center
        mnemonicLabel.lineBreakMode = .byWordWrapping
        mnemonicLabel.textColor = UIColor.ows_white
        mnemonicLabel.alpha = 0.8
        // Button stack view
        let copyButton = OWSFlatButton.button(title: NSLocalizedString("Copy", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(copySeed))
        copyButton.setBackgroundColors(upColor: .clear, downColor: .clear)
        let buttonStackView = UIStackView(arrangedSubviews: [ copyButton, cancelButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        let buttonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        copyButton.set(.height, to: buttonHeight)
        cancelButton.set(.height, to: buttonHeight)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ UIView.spacer(withHeight: 2), titleLabel, subtitleLabel, mnemonicLabel, buttonStackView ])
        stackView.axis = .vertical
        stackView.spacing = 16
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
        stackView.pin(.top, to: .top, of: contentView, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 16)
    }
    
    // MARK: Interaction
    @objc private func copySeed() {
        UIPasteboard.general.string = mnemonic
        dismiss(animated: true, completion: nil)
    }
}
