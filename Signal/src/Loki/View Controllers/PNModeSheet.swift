import PromiseKit

final class PNModeSheet : Sheet, OptionViewDelegate {

    private var optionViews: [OptionView] {
        [ apnsOptionView, backgroundPollingOptionView ]
    }

    private var selectedOptionView: OptionView? {
        return optionViews.first { $0.isSelected }
    }

    // MARK: Components
    private lazy var apnsOptionView = OptionView(title: NSLocalizedString("Apple Push Notification Service", comment: ""), explanation: NSLocalizedString("Session will use the Apple Push Notification service to receive push notifications. You'll be notified of new messages reliably and immediately. Using APNs means that your IP address and device token will be exposed to Apple. If you use push notifications for other apps, this will already be the case. Your IP address and device token will also be exposed to Loki, but your messages will still be onion-routed and end-to-end encrypted, so the contents of your messages will remain completely private.", comment: ""), delegate: self, isRecommended: true)
    private lazy var backgroundPollingOptionView = OptionView(title: NSLocalizedString("Background Polling", comment: ""), explanation: NSLocalizedString("Session will occasionally check for new messages in the background. This guarantees full metadata protection, but message notifications may be significantly delayed.", comment: ""), delegate: self)

    // MARK: Lifecycle
    override func populateContentView() {
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = NSLocalizedString("Push Notifications", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("Session now features two ways to handle push notifications. Make sure to read the descriptions carefully before you choose.", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up options stack view
        let optionsStackView = UIStackView(arrangedSubviews: optionViews)
        optionsStackView.axis = .vertical
        optionsStackView.spacing = Values.smallSpacing
        optionsStackView.alignment = .fill
        // Set up confirm button
        let confirmButton = Button(style: .prominentOutline, size: .medium)
        confirmButton.set(.width, to: 240)
        confirmButton.setTitle(NSLocalizedString("Confirm", comment: ""), for: UIControl.State.normal)
        confirmButton.addTarget(self, action: #selector(confirm), for: UIControl.Event.touchUpInside)
        // Set up dismiss button
        let skipButton = Button(style: .regular, size: .medium)
        skipButton.set(.width, to: 240)
        skipButton.setTitle(NSLocalizedString("Skip", comment: ""), for: UIControl.State.normal)
        skipButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        // Set up button stack view
        let bottomStackView = UIStackView(arrangedSubviews: [ confirmButton, skipButton ])
        bottomStackView.axis = .vertical
        bottomStackView.spacing = isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        bottomStackView.alignment = .fill
        // Set up main stack view
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, optionsStackView, bottomStackView ])
        stackView.axis = .vertical
        stackView.spacing = isIPhone5OrSmaller ? 12 : Values.largeSpacing
        stackView.alignment = .center
        // Set up constraints
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: isIPhone5OrSmaller ? Values.mediumSpacing : Values.largeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: isIPhone5OrSmaller ? Values.mediumSpacing : Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: isIPhone5OrSmaller ? Values.mediumSpacing : Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: (isIPhone5OrSmaller ? Values.mediumSpacing : Values.veryLargeSpacing) + overshoot)
    }

    // MARK: Interaction
    func optionViewDidActivate(_ optionView: OptionView) {
        optionViews.filter { $0 != optionView }.forEach { $0.isSelected = false }
    }

    @objc private func confirm() {
        guard selectedOptionView != nil else {
            let title = NSLocalizedString("Please Pick an Option", comment: "")
            let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            return present(alert, animated: true, completion: nil)
        }
        UserDefaults.standard[.isUsingFullAPNs] = (selectedOptionView == apnsOptionView)
        let syncTokensJob = SyncPushTokensJob(accountManager: AppEnvironment.shared.accountManager, preferences: Environment.shared.preferences)
        syncTokensJob.uploadOnlyIfStale = false
        let _: Promise<Void> = syncTokensJob.run()
        close()
    }

    override func close() {
        UserDefaults.standard[.hasSeenPNModeSheet] = true
        super.close()
    }
}
