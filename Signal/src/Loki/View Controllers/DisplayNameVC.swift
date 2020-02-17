
final class DisplayNameVC : UIViewController {
    private var spacer1HeightConstraint: NSLayoutConstraint!
    private var spacer2HeightConstraint: NSLayoutConstraint!
    private var registerButtonBottomOffsetConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    
    // MARK: Components
    private lazy var displayNameTextField: TextField = {
        let result = TextField(placeholder: NSLocalizedString("Enter a display name", comment: ""))
        result.layer.borderColor = Colors.text.cgColor
        return result
    }()
    
    // MARK: Settings
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set up navigation bar
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
        // Set up logo image view
        let logoImageView = UIImageView()
        logoImageView.image = #imageLiteral(resourceName: "SessionGreen32")
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.set(.width, to: 32)
        logoImageView.set(.height, to: 32)
        navigationItem.titleView = logoImageView
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isSmallScreen ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = NSLocalizedString("Pick your display name", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = "This will be your name when you use Session."
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let spacer1 = UIView()
        spacer1HeightConstraint = spacer1.set(.height, to: isSmallScreen ? Values.smallSpacing : Values.veryLargeSpacing)
        let spacer2 = UIView()
        spacer2HeightConstraint = spacer2.set(.height, to: isSmallScreen ? Values.smallSpacing : Values.veryLargeSpacing)
        let bottomSpacer = UIView.vStretchingSpacer()
        let registerButtonBottomOffsetSpacer = UIView()
        registerButtonBottomOffsetConstraint = registerButtonBottomOffsetSpacer.set(.height, to: Values.onboardingButtonBottomOffset)
        // Set up register button
        let registerButton = Button(style: .prominentFilled, size: .large)
        registerButton.setTitle(NSLocalizedString("Continue", comment: ""), for: UIControl.State.normal)
        registerButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        registerButton.addTarget(self, action: #selector(register), for: UIControl.Event.touchUpInside)
        // Set up register button container
        let registerButtonContainer = UIView()
        registerButtonContainer.addSubview(registerButton)
        registerButton.pin(.leading, to: .leading, of: registerButtonContainer, withInset: Values.massiveSpacing)
        registerButton.pin(.top, to: .top, of: registerButtonContainer)
        registerButtonContainer.pin(.trailing, to: .trailing, of: registerButton, withInset: Values.massiveSpacing)
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
    
    // MARK: General
    @objc private func dismissKeyboard() {
        displayNameTextField.resignFirstResponder()
    }
    
    // MARK: Updating
    @objc private func handleKeyboardWillChangeFrameNotification(_ notification: Notification) {
        guard let newHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size.height else { return }
        bottomConstraint.constant = -newHeight // Negative due to how the constraint is set up
        registerButtonBottomOffsetConstraint.constant = isSmallScreen ? Values.smallSpacing : Values.largeSpacing
        spacer1HeightConstraint.constant = isSmallScreen ? Values.smallSpacing : Values.mediumSpacing
        spacer2HeightConstraint.constant = isSmallScreen ? Values.smallSpacing : Values.mediumSpacing
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func handleKeyboardWillHideNotification(_ notification: Notification) {
        bottomConstraint.constant = 0
        registerButtonBottomOffsetConstraint.constant = Values.onboardingButtonBottomOffset
        spacer1HeightConstraint.constant = isSmallScreen ? Values.smallSpacing : Values.veryLargeSpacing
        spacer2HeightConstraint.constant = isSmallScreen ? Values.smallSpacing : Values.veryLargeSpacing
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: Interaction
    @objc private func register() {
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        }
        let displayName = displayNameTextField.text!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            return showError(title: NSLocalizedString("Please pick a display name", comment: ""))
        }
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ ")
        let hasInvalidCharacters = !displayName.allSatisfy { $0.unicodeScalars.allSatisfy { allowedCharacters.contains($0) } }
        guard !hasInvalidCharacters else {
            return showError(title: NSLocalizedString("Please pick a display name that consists of only a-z, A-Z, 0-9 and _ characters", comment: ""))
        }
        guard !OWSProfileManager.shared().isProfileNameTooLong(displayName) else {
            return showError(title: NSLocalizedString("Please pick a shorter display name", comment: ""))
        }
        TSAccountManager.sharedInstance().didRegister()
        OWSProfileManager.shared().updateLocalProfileName(displayName, avatarImage: nil, success: { }, failure: { _ in }, requiresSync: false) // Try to save the user name but ignore the result
        let homeVC = HomeVC()
        navigationController!.setViewControllers([ homeVC ], animated: true)
    }
}
