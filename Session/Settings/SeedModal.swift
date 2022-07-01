// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUtilitiesKit

@objc(LKSeedModal)
final class SeedModal: Modal {

    private let mnemonic: String = {
        if let hexEncodedSeed: String = Identity.fetchHexEncodedSeed() {
            return Mnemonic.encode(hexEncodedString: hexEncodedSeed)
        }
        
        // Legacy account
        return Mnemonic.encode(hexEncodedString: Identity.fetchUserPrivateKey()!.toHexString())
    }()
    
    // MARK: - Lifecycle
    
    override func populateContentView() {
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = NSLocalizedString("modal_seed_title", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        
        // Set up mnemonic label
        let mnemonicLabel = UILabel()
        mnemonicLabel.textColor = Colors.text
        mnemonicLabel.font = Fonts.spaceMono(ofSize: Values.smallFontSize)
        mnemonicLabel.text = mnemonic
        mnemonicLabel.numberOfLines = 0
        mnemonicLabel.lineBreakMode = .byWordWrapping
        mnemonicLabel.textAlignment = .center
        
        // Set up mnemonic label container
        let mnemonicLabelContainer = UIView()
        mnemonicLabelContainer.addSubview(mnemonicLabel)
        mnemonicLabel.pin(to: mnemonicLabelContainer, withInset: isIPhone6OrSmaller ? 4 : Values.smallSpacing)
        mnemonicLabelContainer.layer.cornerRadius = TextField.cornerRadius
        mnemonicLabelContainer.layer.borderWidth = 1
        mnemonicLabelContainer.layer.borderColor = Colors.text.cgColor
        
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("modal_seed_explanation", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textAlignment = .center
        
        // Set up copy button
        let copyButton = UIButton()
        copyButton.set(.height, to: Values.mediumButtonHeight)
        copyButton.layer.cornerRadius = Modal.buttonCornerRadius
        copyButton.backgroundColor = Colors.buttonBackground
        copyButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        copyButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        copyButton.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        copyButton.addTarget(self, action: #selector(copySeed), for: UIControl.Event.touchUpInside)
        
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, copyButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        
        // Content stack view
        let contentStackView = UIStackView(arrangedSubviews: [ titleLabel, mnemonicLabelContainer, explanationLabel ])
        contentStackView.axis = .vertical
        contentStackView.spacing = Values.largeSpacing
        
        // Set up stack view
        let spacing = Values.largeSpacing - Values.smallFontSize / 2
        let stackView = UIStackView(arrangedSubviews: [ contentStackView, buttonStackView ])
        stackView.axis = .vertical
        stackView.spacing = spacing
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: spacing)
        
        // Mark seed as viewed
        Storage.shared.writeAsync { db in db[.hasViewedSeed] = true }
    }
    
    // MARK: - Interaction
    
    @objc private func copySeed() {
        UIPasteboard.general.string = mnemonic
        dismiss(animated: true, completion: nil)
    }
}
