// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit

final class DisplayNameVC: BaseVC {
    private var spacer1HeightConstraint: NSLayoutConstraint!
    private var spacer2HeightConstraint: NSLayoutConstraint!
    private var registerButtonBottomOffsetConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    
    // MARK: - Components
    
    private lazy var displayNameTextField: TextField = {
        let result = TextField(placeholder: "vc_display_name_text_field_hint".localized())
        result.themeBorderColor = .textPrimary
        result.accessibilityLabel = "Display name text field"
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpNavBarSessionIcon()
        
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = "vc_display_name_title_2".localized()
        titleLabel.themeTextColor = .textPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.numberOfLines = 0
        
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = "vc_display_name_explanation".localized()
        explanationLabel.themeTextColor = .textPrimary
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.numberOfLines = 0
        
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let spacer1 = UIView()
        spacer1HeightConstraint = spacer1.set(.height, to: isIPhone5OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing)
        let spacer2 = UIView()
        spacer2HeightConstraint = spacer2.set(.height, to: isIPhone5OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing)
        let bottomSpacer = UIView.vStretchingSpacer()
        let registerButtonBottomOffsetSpacer = UIView()
        registerButtonBottomOffsetConstraint = registerButtonBottomOffsetSpacer.set(.height, to: Values.onboardingButtonBottomOffset)
        
        // Set up register button
        let registerButton = SessionButton(style: .filled, size: .large)
        registerButton.setTitle("continue_2".localized(), for: UIControl.State.normal)
        registerButton.addTarget(self, action: #selector(register), for: UIControl.Event.touchUpInside)
        
        // Set up register button container
        let registerButtonContainer = UIView()
        registerButtonContainer.addSubview(registerButton)
        if UIDevice.current.isIPad {
            registerButton.set(.width, to: Values.iPadButtonWidth)
            registerButton.center(in: registerButtonContainer)
        }
        else {
            registerButton.pin(.leading, to: .leading, of: registerButtonContainer, withInset: Values.massiveSpacing)
            registerButtonContainer.pin(.trailing, to: .trailing, of: registerButton, withInset: Values.massiveSpacing)
        }
        registerButton.pin(.top, to: .top, of: registerButtonContainer)
        registerButtonContainer.pin(.bottom, to: .bottom, of: registerButton)
        
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ titleLabel, spacer1, explanationLabel, spacer2, displayNameTextField ])
        topStackView.axis = .vertical
        topStackView.alignment = .fill
        
        // Set up top stack view container
        let topStackViewContainer = UIView()
        topStackViewContainer.addSubview(topStackView)
        topStackView.pin(.leading, to: .leading, of: topStackViewContainer, withInset: Values.veryLargeSpacing)
        topStackView.pin(.top, to: .top, of: topStackViewContainer)
        topStackViewContainer.pin(.trailing, to: .trailing, of: topStackView, withInset: Values.veryLargeSpacing)
        topStackViewContainer.pin(.bottom, to: .bottom, of: topStackView)
        
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, topStackViewContainer, bottomSpacer, registerButtonContainer, registerButtonBottomOffsetSpacer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        view.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: view)
        mainStackView.pin(.top, to: .top, of: view)
        mainStackView.pin(.trailing, to: .trailing, of: view)
        bottomConstraint = mainStackView.pin(.bottom, to: .bottom, of: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
        
        // Dismiss keyboard on tap
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGestureRecognizer)
        
        // Listen to keyboard notifications
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillChangeFrameNotification(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleKeyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        displayNameTextField.becomeFirstResponder()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - General
    
    @objc private func dismissKeyboard() {
        displayNameTextField.resignFirstResponder()
    }
    
    // MARK: - Updating
    
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        
        bottomConstraint.constant = -newHeight // Negative due to how the constraint is set up
        registerButtonBottomOffsetConstraint.constant = isIPhone5OrSmaller ? Values.smallSpacing : Values.largeSpacing
        spacer1HeightConstraint.constant = isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        spacer2HeightConstraint.constant = isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        bottomConstraint.constant = 0
        registerButtonBottomOffsetConstraint.constant = Values.onboardingButtonBottomOffset
        spacer1HeightConstraint.constant = isIPhone5OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing
        spacer2HeightConstraint.constant = isIPhone5OrSmaller ? Values.smallSpacing : Values.veryLargeSpacing
        
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Interaction
    
    @objc private func register() {
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        }
        let displayName = displayNameTextField.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            return showError(title: NSLocalizedString("vc_display_name_display_name_missing_error", comment: ""))
        }
        guard !ProfileManager.isToLong(profileName: displayName) else {
            return showError(title: NSLocalizedString("vc_display_name_display_name_too_long_error", comment: ""))
        }
        
        // Try to save the user name but ignore the result
        ProfileManager.updateLocal(
            queue: DispatchQueue.global(qos: .default),
            profileName: displayName,
            image: nil,
            imageFilePath: nil
        )
        let pnModeVC = PNModeVC()
        navigationController?.pushViewController(pnModeVC, animated: true)
    }
}
