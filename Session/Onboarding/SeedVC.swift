// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit
import SignalUtilitiesKit

final class SeedVC: BaseVC {
    private let mnemonic: String = {
        if let hexEncodedSeed: String = Identity.fetchHexEncodedSeed() {
            return Mnemonic.encode(hexEncodedString: hexEncodedSeed)
        }
        
        // Legacy account
        return Mnemonic.encode(hexEncodedString: Identity.fetchUserPrivateKey()!.toHexString())
    }()
    
    private lazy var redactedMnemonic: String = {
        if isIPhone5OrSmaller {
            return "▆▆▆▆ ▆▆▆▆▆▆ ▆▆▆ ▆▆▆▆▆▆▆ ▆▆ ▆▆▆▆ ▆▆▆ ▆▆▆▆▆ ▆▆▆ ▆ ▆▆▆▆ ▆▆ ▆▆▆▆▆▆▆ ▆▆▆▆▆"
        }
        
        return "▆▆▆▆ ▆▆▆▆▆▆ ▆▆▆ ▆▆▆▆▆▆▆ ▆▆ ▆▆▆▆ ▆▆▆ ▆▆▆▆▆ ▆▆▆ ▆ ▆▆▆▆ ▆▆ ▆▆▆▆▆▆▆ ▆▆▆▆▆ ▆▆▆▆▆▆▆▆ ▆▆ ▆▆▆ ▆▆▆▆▆▆▆"
    }()
    
    // MARK: - Components
    
    private lazy var seedReminderView: SeedReminderView = {
        let result = SeedReminderView(hasContinueButton: false)
        result.subtitle = "view_seed_reminder_subtitle_2".localized()
        result.setProgress(0.9, animated: false)
        
        ThemeManager.onThemeChange(observer: result) { [weak result] _, primaryColor in
            let title = "You're almost finished! 90%"
            let attributedTitle = NSMutableAttributedString(string: title)
            attributedTitle.addAttribute(
                .foregroundColor,
                value: primaryColor.color,
                range: (title as NSString).range(of: "90%")
            )
            result?.title = attributedTitle
        }
        
        return result
    }()
    
    private lazy var mnemonicLabel: UILabel = {
        let result = UILabel()
        result.font = Fonts.spaceMono(ofSize: Values.mediumFontSize)
        result.themeTextColor = .primary
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var copyButton: SessionButton = {
        let result = SessionButton(style: .bordered, size: .large)
        result.setTitle("copy".localized(), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyMnemonic), for: UIControl.Event.touchUpInside)
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setNavBarTitle("vc_seed_title".localized())
        
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.themeTintColor = .textPrimary
        navigationItem.leftBarButtonItem = closeButton
        
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = "vc_seed_title_2".localized()
        titleLabel.themeTextColor = .textPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.numberOfLines = 0
        
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = "vc_seed_explanation".localized()
        explanationLabel.themeTextColor = .textPrimary
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.numberOfLines = 0
        
        // Set up mnemonic label
        mnemonicLabel.text = redactedMnemonic
        let mnemonicLabelGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(revealMnemonic))
        mnemonicLabel.addGestureRecognizer(mnemonicLabelGestureRecognizer)
        mnemonicLabel.isUserInteractionEnabled = true
        mnemonicLabel.isEnabled = true
        
        // Set up mnemonic label container
        let mnemonicLabelContainer = UIView()
        mnemonicLabelContainer.addSubview(mnemonicLabel)
        mnemonicLabel.pin(to: mnemonicLabelContainer, withInset: isIPhone6OrSmaller ? Values.smallSpacing : Values.mediumSpacing)
        mnemonicLabelContainer.themeBorderColor = .textPrimary
        mnemonicLabelContainer.layer.cornerRadius = TextField.cornerRadius
        mnemonicLabelContainer.layer.borderWidth = 1
        
        // Set up call to action label
        let callToActionLabel = UILabel()
        callToActionLabel.font = .systemFont(ofSize: isIPhone5OrSmaller ? Values.smallFontSize : Values.mediumFontSize)
        callToActionLabel.text = "vc_seed_reveal_button_title".localized()
        callToActionLabel.themeTextColor = .textSecondary
        callToActionLabel.textAlignment = .center
        
        let callToActionLabelGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(revealMnemonic))
        callToActionLabel.addGestureRecognizer(callToActionLabelGestureRecognizer)
        callToActionLabel.isUserInteractionEnabled = true
        callToActionLabel.isEnabled = true
        
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        
        // Set up copy button container
        let copyButtonContainer = UIView()
        copyButtonContainer.addSubview(copyButton)
        copyButton.pin(.leading, to: .leading, of: copyButtonContainer, withInset: Values.massiveSpacing)
        copyButton.pin(.top, to: .top, of: copyButtonContainer)
        copyButtonContainer.pin(.trailing, to: .trailing, of: copyButton, withInset: Values.massiveSpacing)
        copyButtonContainer.pin(.bottom, to: .bottom, of: copyButton)
        
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ titleLabel, UIView.spacer(withHeight: isIPhone6OrSmaller ? Values.smallSpacing : Values.largeSpacing), explanationLabel,
            UIView.spacer(withHeight: isIPhone6OrSmaller ? Values.smallSpacing + 2 : Values.largeSpacing), mnemonicLabelContainer ])
        if !isIPhone5OrSmaller {
            topStackView.addArrangedSubview(UIView.spacer(withHeight: Values.smallSpacing))
            topStackView.addArrangedSubview(callToActionLabel) // Not that important and it really gets in the way on small screens
        }
        topStackView.axis = .vertical
        topStackView.alignment = .fill
        
        // Set up top stack view container
        let topStackViewContainer = UIView()
        topStackViewContainer.addSubview(topStackView)
        topStackView.pin(.leading, to: .leading, of: topStackViewContainer, withInset: Values.veryLargeSpacing)
        topStackView.pin(.top, to: .top, of: topStackViewContainer)
        topStackViewContainer.pin(.trailing, to: .trailing, of: topStackView, withInset: Values.veryLargeSpacing)
        topStackViewContainer.pin(.bottom, to: .bottom, of: topStackView)
        
        // Set up seed reminder view
        view.addSubview(seedReminderView)
        seedReminderView.pin(.leading, to: .leading, of: view)
        seedReminderView.pin(.top, to: .top, of: view)
        seedReminderView.pin(.trailing, to: .trailing, of: view)
        
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, topStackViewContainer, bottomSpacer, copyButtonContainer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        mainStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: Values.mediumSpacing, trailing: 0)
        mainStackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(mainStackView)
        
        mainStackView.pin(.leading, to: .leading, of: view)
        mainStackView.pin(.top, to: .bottom, of: seedReminderView)
        mainStackView.pin(.trailing, to: .trailing, of: view)
        mainStackView.pin(.bottom, to: .bottom, of: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
    }
    
    // MARK: - General
    
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("copy".localized(), for: UIControl.State.normal)
        }, completion: nil)
    }
    
    // MARK: - Interaction
    
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func revealMnemonic() {
        UIView.transition(with: mnemonicLabel, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.mnemonicLabel.text = self.mnemonic
            self.mnemonicLabel.themeTextColor = .textPrimary
        }, completion: nil)
        
        UIView.transition(with: seedReminderView.titleLabel, duration: 0.25, options: .transitionCrossDissolve, animations: {
            ThemeManager.onThemeChange(observer: self.seedReminderView) { [weak self] _, primaryColor in
                let title = "Account Secured! 100%"
                let attributedTitle = NSMutableAttributedString(string: title)
                attributedTitle.addAttribute(
                    .foregroundColor,
                    value: primaryColor.color,
                    range: (title as NSString).range(of: "100%")
                )
                self?.seedReminderView.title = attributedTitle
            }
        }, completion: nil)
        
        UIView.transition(with: seedReminderView.subtitleLabel, duration: 1, options: .transitionCrossDissolve, animations: {
            self.seedReminderView.subtitle = "view_seed_reminder_subtitle_3".localized()
        }, completion: nil)
        seedReminderView.setProgress(1, animated: true)
        
        Storage.shared.writeAsync { db in db[.hasViewedSeed] = true }
    }
    
    @objc private func copyMnemonic() {
        revealMnemonic()
        
        UIPasteboard.general.string = mnemonic
        
        copyButton.isUserInteractionEnabled = false
        
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("copied".localized(), for: UIControl.State.normal)
        }, completion: nil)
        
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
}
