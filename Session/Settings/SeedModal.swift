// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit

final class SeedModal: Modal {
    private let mnemonic: String = {
        if let hexEncodedSeed: String = Identity.fetchHexEncodedSeed() {
            return Mnemonic.encode(hexEncodedString: hexEncodedSeed)
        }
        
        // Legacy account
        return Mnemonic.encode(hexEncodedString: Identity.fetchUserPrivateKey()!.toHexString())
    }()
    
    // MARK: - Initialization
    
    override init(targetView: UIView? = nil, afterClosed: (() -> ())? = nil) {
        super.init(targetView: targetView, afterClosed: afterClosed)
        
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Components
    
    private let titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.text = "modal_seed_title".localized()
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private let explanationLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = "modal_seed_explanation".localized()
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var mnemonicLabelContainer: UIView = {
        let result: UIView = UIView()
        result.themeBorderColor = .textPrimary
        result.layer.cornerRadius = TextField.cornerRadius
        result.layer.borderWidth = 1
        
        return result
    }()
    
    private lazy var mnemonicLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = Fonts.spaceMono(ofSize: Values.smallFontSize)
        result.text = mnemonic
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var copyButton: UIButton = {
        let result: UIButton = Modal.createButton(
            title: "copy".localized(),
            titleColor: .textPrimary
        )
        result.addTarget(self, action: #selector(copySeed), for: .touchUpInside)
        
        return result
    }()
    
    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ copyButton, cancelButton ])
        result.axis = .horizontal
        result.spacing = Values.mediumSpacing
        result.distribution = .fillEqually
        
        return result
    }()
    
    private lazy var contentStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, mnemonicLabelContainer ])
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.isLayoutMarginsRelativeArrangement = true
        result.layoutMargins = UIEdgeInsets(
            top: Values.largeSpacing,
            leading: Values.largeSpacing,
            bottom: Values.verySmallSpacing,
            trailing: Values.largeSpacing
        )
        
        return result
    }()
    
    private lazy var mainStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ contentStackView, buttonStackView ])
        result.axis = .vertical
        result.spacing = Values.largeSpacing - Values.smallFontSize / 2
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func populateContentView() {
        contentView.addSubview(mainStackView)
        
        mainStackView.pin(to: contentView)
        
        mnemonicLabelContainer.addSubview(mnemonicLabel)
        mnemonicLabel.pin(to: mnemonicLabelContainer, withInset: isIPhone6OrSmaller ? 4 : Values.smallSpacing)
        
        // Mark seed as viewed
        Storage.shared.writeAsync { db in db[.hasViewedSeed] = true }
    }
    
    // MARK: - Interaction
    
    @objc private func copySeed() {
        UIPasteboard.general.string = mnemonic
        
        dismiss(animated: true, completion: nil)
    }
}
