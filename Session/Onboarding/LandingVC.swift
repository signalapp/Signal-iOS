// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class LandingVC: BaseVC {
    
    // MARK: - Components
    
    private lazy var fakeChatView: FakeChatView = {
        let result = FakeChatView()
        result.set(.height, to: LandingVC.fakeChatViewHeight)
        
        return result
    }()
    
    private lazy var registerButton: OutlineButton = {
        let result = OutlineButton(style: .filled, size: .large)
        result.setTitle("vc_landing_register_button_title".localized(), for: .normal)
        result.addTarget(self, action: #selector(register), for: .touchUpInside)
        
        return result
    }()
    
    private lazy var restoreButton: OutlineButton = {
        let result = OutlineButton(style: .regular, size: .large)
        result.setTitle("vc_landing_restore_button_title".localized(), for: .normal)
        result.addTarget(self, action: #selector(restore), for: .touchUpInside)
        
        return result
    }()
    
    // MARK: - Settings
    
    private static let fakeChatViewHeight = isIPhone5OrSmaller ? CGFloat(234) : CGFloat(260)
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpNavBarSessionIcon()
        
        // Title label
        let titleLabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = "vc_landing_title_2".localized()
        titleLabel.themeTextColor = .textPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.numberOfLines = 0
        
        // Title label container
        let titleLabelContainer = UIView()
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.pin(.leading, to: .leading, of: titleLabelContainer, withInset: Values.veryLargeSpacing)
        titleLabel.pin(.top, to: .top, of: titleLabelContainer)
        titleLabelContainer.pin(.trailing, to: .trailing, of: titleLabel, withInset: Values.veryLargeSpacing)
        titleLabelContainer.pin(.bottom, to: .bottom, of: titleLabel)
        
        // Spacers
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        
        // Link button
        let linkButton = UIButton()
        linkButton.titleLabel?.font = .boldSystemFont(ofSize: Values.smallFontSize)
        linkButton.setTitle("vc_landing_link_button_title".localized(), for: .normal)
        linkButton.setThemeTitleColor(.textPrimary, for: .normal)
        linkButton.addTarget(self, action: #selector(link), for: .touchUpInside)
        
        // Link button container
        let linkButtonContainer = UIView()
        linkButtonContainer.set(.height, to: Values.onboardingButtonBottomOffset)
        linkButtonContainer.addSubview(linkButton)
        linkButton.center(.horizontal, in: linkButtonContainer)
        
        let isIPhoneX = ((UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0) > 0)
        linkButton.centerYAnchor.constraint(equalTo: linkButtonContainer.centerYAnchor, constant: isIPhoneX ? -4 : 0).isActive = true
        
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ registerButton, restoreButton ])
        buttonStackView.axis = .vertical
        buttonStackView.spacing = isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        buttonStackView.alignment = .fill
        if UIDevice.current.isIPad {
            registerButton.set(.width, to: Values.iPadButtonWidth)
            restoreButton.set(.width, to: Values.iPadButtonWidth)
            buttonStackView.alignment = .center
        }
        
        // Button stack view container
        let buttonStackViewContainer = UIView()
        buttonStackViewContainer.addSubview(buttonStackView)
        buttonStackView.pin(.leading, to: .leading, of: buttonStackViewContainer, withInset: isIPhone5OrSmaller ? CGFloat(52) : Values.massiveSpacing)
        buttonStackView.pin(.top, to: .top, of: buttonStackViewContainer)
        buttonStackViewContainer.pin(.trailing, to: .trailing, of: buttonStackView, withInset: isIPhone5OrSmaller ? CGFloat(52) : Values.massiveSpacing)
        buttonStackViewContainer.pin(.bottom, to: .bottom, of: buttonStackView)
        
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, titleLabelContainer, UIView.spacer(withHeight: isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing), fakeChatView, bottomSpacer, buttonStackViewContainer, linkButtonContainer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        view.addSubview(mainStackView)
        mainStackView.pin(to: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
    }
    
    // MARK: - Interaction
    
    @objc private func register() {
        let registerVC = RegisterVC()
        navigationController!.pushViewController(registerVC, animated: true)
    }
    
    @objc private func restore() {
        let restoreVC = RestoreVC()
        navigationController!.pushViewController(restoreVC, animated: true)
    }
    
    @objc private func link() {
        let linkVC = LinkDeviceVC()
        navigationController!.pushViewController(linkVC, animated: true)
    }
}
