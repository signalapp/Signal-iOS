
final class AccountDetailsViewController : OnboardingBaseViewController {
    
    private lazy var userNameTextField: UITextField = {
        let result = UITextField()
        result.textColor = Theme.primaryColor
        result.font = UIFont.ows_dynamicTypeBodyClamped
        result.textAlignment = .center
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Display Name (Optional)", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = UIColor.lokiGreen()
        result.accessibilityIdentifier = "onboarding.accountDetailsStep.userNameTextField"
        result.keyboardAppearance = .dark
        return result
    }()

    private var normalizedUserName: String? {
        let result = userNameTextField.text!.ows_stripped()
        return !result.isEmpty ? result : nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero
        let titleLabel = self.createTitleLabel(text: NSLocalizedString("Create Your Loki Messenger Account", comment: ""))
        titleLabel.accessibilityIdentifier = "onboarding.accountDetailsStep.titleLabel"
        let topSpacer = UIView.vStretchingSpacer()
        let displayNameLabel = createExplanationLabel(text: NSLocalizedString("Enter a name to be shown to your contacts", comment: ""))
        displayNameLabel.accessibilityIdentifier = "onboarding.accountDetailsStep.displayNameLabel"
        let bottomSpacer = UIView.vStretchingSpacer()
        let nextButton = createButton(title: NSLocalizedString("Next", comment: ""), selector: #selector(handleNextButtonPressed))
        nextButton.accessibilityIdentifier = "onboarding.accountDetailsStep.nextButton"
        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            displayNameLabel,
            UIView.spacer(withHeight: 8),
            userNameTextField,
            bottomSpacer,
            nextButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        userNameTextField.becomeFirstResponder()
    }
    
    @objc private func handleNextButtonPressed() {
        if let normalizedName = normalizedUserName {
            guard !OWSProfileManager.shared().isProfileNameTooLong(normalizedName) else {
                return OWSAlerts.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_PROFILE_NAME_TOO_LONG", comment: "Error message shown when user tries to update profile with a profile name that is too long"))
            }
        }
        onboardingController.pushKeyPairViewController(from: self, userName: normalizedUserName)
    }
}
