
final class DisplayNameVC : OnboardingBaseViewController {
    
    private lazy var userNameTextField: UITextField = {
        let result = UITextField()
        result.textColor = Theme.primaryColor
        result.font = .ows_dynamicTypeBodyClamped
        result.textAlignment = .center
        let placeholder = NSMutableAttributedString(string: NSLocalizedString("Display Name", comment: ""))
        placeholder.addAttribute(.foregroundColor, value: Theme.placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        result.attributedPlaceholder = placeholder
        result.tintColor = .lokiGreen()
        result.accessibilityIdentifier = "onboarding.accountDetailsStep.userNameTextField"
        result.keyboardAppearance = .dark
        return result
    }()
    
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
        Analytics.shared.track("Display Name Screen Viewed")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        userNameTextField.becomeFirstResponder()
    }
    
    @objc private func handleNextButtonPressed() {
        let displayName = userNameTextField.text!.ows_stripped()
        guard !displayName.isEmpty else {
            return OWSAlerts.showErrorAlert(message: NSLocalizedString("Please pick a display name", comment: ""))
        }
        guard !OWSProfileManager.shared().isProfileNameTooLong(displayName) else {
            return OWSAlerts.showErrorAlert(message: NSLocalizedString("Please pick a shorter display name", comment: ""))
        }
        TSAccountManager.sharedInstance().didRegister()
        UserDefaults.standard.set(true, forKey: "didUpdateForMainnet")
        onboardingController.verificationDidComplete(fromView: self)
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.setUpDefaultPublicChatsIfNeeded()
        appDelegate.createRSSFeedsIfNeeded()
        LokiPublicChatManager.shared.startPollersIfNeeded()
        appDelegate.startRSSFeedPollersIfNeeded()
        OWSProfileManager.shared().updateLocalProfileName(displayName, avatarImage: nil, success: { }, failure: { }) // Try to save the user name but ignore the result
    }
}
