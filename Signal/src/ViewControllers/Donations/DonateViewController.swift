//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import Lottie
import SignalUI
import SignalServiceKit
import SignalMessaging

class DonateViewController: OWSViewController, OWSNavigationChildController {
    private var backgroundColor: UIColor {
        OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
    }
    static let cornerRadius: CGFloat = 18
    static var bubbleBackgroundColor: CGColor { DonationViewsUtil.bubbleBackgroundColor.cgColor }
    static var selectedColor: CGColor { Theme.accentBlueColor.cgColor }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .clear }
    public var navbarBackgroundColorOverride: UIColor { backgroundColor }

    private static func commonStack() -> UIStackView {
        let result = UIStackView()
        result.axis = .vertical
        result.alignment = .fill
        result.spacing = 20
        return result
    }

    private var navigationBar: OWSNavigationBar? {
        navigationController?.navigationBar as? OWSNavigationBar
    }

    // MARK: - Initialization

    internal var state: State {
        didSet {
            Logger.info("[Donations] DonateViewController state changed to \(state.debugDescription)")
            render(oldState: oldValue)
        }
    }

    enum FinishResult {
        case completedDonation(donateSheet: DonateViewController, badgeThanksSheet: BadgeThanksSheet)
        case monthlySubscriptionCancelled(donateSheet: DonateViewController, toastText: String)
    }
    internal let onFinished: (FinishResult) -> Void

    private var scrollToOneTimeContinueButtonWhenKeyboardAppears = false

    public init(
        startingDonationMode: DonationMode,
        onFinished: @escaping (FinishResult) -> Void
    ) {
        self.state = .init(donationMode: startingDonationMode)
        self.onFinished = onFinished

        super.init()
    }

    // MARK: - View callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()

        render(oldState: nil)
        loadAndUpdateState()

        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinHeightToSuperview()

        let margin: CGFloat = 20
        let topMargin: CGFloat = navigationBar == nil ? margin : 0
        stackView.layoutMargins = .init(
            top: topMargin,
            leading: margin,
            bottom: margin,
            trailing: margin
        )
        stackView.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperview()
        scrollView.autoPinEdge(toSuperviewEdge: .top)
        scrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didKeyboardShow),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render(oldState: nil)
    }

    // MARK: - Events

    @objc
    private func didDonationModeChange() {
        let rawValue = donationModePickerView.selectedSegmentIndex
        guard let newValue = DonationMode(rawValue: rawValue) else {
            owsFail("[Donations] Unexpected donation mode")
        }
        state = state.selectDonationMode(newValue)
    }

    private func addAnimationView(anchor: UIView, name: String) {
        if UIAccessibility.isReduceMotionEnabled { return }

        let animationView = AnimationView(name: name)
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .forceFinish
        animationView.isUserInteractionEnabled = false
        stackView.addSubview(animationView)
        animationView.autoPinEdge(.bottom, to: .top, of: anchor, withOffset: 30)
        animationView.autoPinEdge(.leading, to: .leading, of: anchor)
        animationView.autoMatch(.width, to: .width, of: anchor)
        animationView.play { _ in
            animationView.removeFromSuperview()
        }
    }

    private func didSelectOneTimeAmount(
        amount: FiatMoney,
        animationAnchor: UIView,
        animationName: String
    ) {
        state = state.selectOneTimeAmount(.selectedPreset(amount: amount))
        addAnimationView(anchor: animationAnchor, name: animationName)
    }

    @objc
    private func didKeyboardShow() {
        if scrollToOneTimeContinueButtonWhenKeyboardAppears {
            scrollView.scrollIntoView(subview: oneTimeContinueButton)
            scrollToOneTimeContinueButtonWhenKeyboardAppears = false
        }
    }

    @objc
    private func didTapOneTimeCustomAmountTextField() {
        guard let oneTime = state.oneTime else {
            owsFail("[Donations] Expected one-time state but it was not loaded")
        }
        state = state.selectOneTimeAmount(.choseCustomAmount(
            amount: FiatMoney(currencyCode: oneTime.selectedCurrencyCode, value: 0)
        ))

        oneTimeCustomAmountTextField.becomeFirstResponder()

        scrollToOneTimeContinueButtonWhenKeyboardAppears = true
    }

    @objc
    private func didTapMonthlySubscriptionLevelView(_ sender: UIGestureRecognizer) {
        guard let view = sender.view as? MonthlySubscriptionLevelView else {
            owsFail("[Donations] Tapped something other than a monthly subscription level view")
        }
        state = state.selectSubscriptionLevel(view.subscriptionLevel)
        addAnimationView(anchor: view, name: view.animationName)
    }

    private func startApplePay(
        with amount: FiatMoney,
        donationMode: DonationMode
    ) {
        SubscriptionManager.terminateTransactionIfPossible = false

        let paymentRequest = DonationUtilities.newPaymentRequest(
            for: amount,
            isRecurring: {
                switch donationMode {
                case .oneTime: return false
                case .monthly: return true
                }
            }()
        )
        let paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        paymentController.delegate = self
        paymentController.present { presented in
            if !presented {
                // This can happen under normal conditions if the user double-taps the button,
                // but may also indicate a problem.
                Logger.warn("[Donations] Failed to present payment controller")
            }
        }
    }

    private func presentChoosePaymentMethodSheet(
        amount: FiatMoney,
        badge: ProfileBadge?,
        donationMode: DonationMode
    ) {
        oneTimeCustomAmountTextField.resignFirstResponder()

        let sheet = DonateChoosePaymentMethodSheet(
            amount: amount,
            badge: badge,
            donationMode: donationMode.forChoosePaymentMethodSheet
        ) { [weak self] sheet in
            sheet.dismiss(animated: true)
            self?.startApplePay(with: amount, donationMode: donationMode)
        }
        present(sheet, animated: true)
    }

    private func didTapToContinueOneTimeDonation() {
        guard let oneTime = state.oneTime else {
            owsFail("[Donations] Expected the one-time state to be loaded. This should be impossible in the UI")
        }

        func showError(_ text: String) {
            let actionSheet = ActionSheetController(message: text)
            actionSheet.addAction(.init(
                title: CommonStrings.okayButton,
                style: .cancel,
                handler: nil
            ))
            presentActionSheet(actionSheet)
        }

        switch oneTime.paymentRequest {
        case .noAmountSelected:
            showError(NSLocalizedString(
                "DONATE_SCREEN_ERROR_NO_AMOUNT_SELECTED",
                comment: "If the user tries to donate to Signal but no amount is selected, this error message is shown."
            ))
        case .amountIsTooSmall:
            showError(NSLocalizedString(
                "DONATE_SCREEN_ERROR_SELECT_A_LARGER_AMOUNT",
                comment: "If the user tries to donate to Signal but they've entered an amount that's too small, this error message is shown."
            ))
        case .amountIsTooLarge:
            showError(NSLocalizedString(
                "DONATE_SCREEN_ERROR_SELECT_A_SMALLER_AMOUNT",
                comment: "If the user tries to donate to Signal but they've entered an amount that's too large, this error message is shown."
            ))
        case let .canContinue(amount):
            presentChoosePaymentMethodSheet(
                amount: amount,
                badge: oneTime.profileBadge,
                donationMode: .oneTime
            )
        }
    }

    private func didTapToContinueMonthlyDonation() {
        guard let monthlyPaymentRequest = state.monthly?.paymentRequest else {
            owsFail("[Donations] Cannot make monthly donation. This should be prevented in the UI")
        }
        presentChoosePaymentMethodSheet(
            amount: monthlyPaymentRequest.amount,
            badge: monthlyPaymentRequest.profileBadge,
            donationMode: .monthly
        )
    }

    private func didTapToUpdateMonthlyDonation() {
        guard let monthlyPaymentRequest = state.monthly?.paymentRequest else {
            owsFail("[Donations] Cannot update monthly donation. This should be prevented in the UI")
        }

        let currencyString = DonationUtilities.format(money: monthlyPaymentRequest.amount)
        let title = NSLocalizedString(
            "SUSTAINER_VIEW_UPDATE_SUBSCRIPTION_CONFIRMATION_TITLE",
            comment: "Update Subscription? Action sheet title"
        )
        let message = String(
            format: NSLocalizedString(
                "SUSTAINER_VIEW_UPDATE_SUBSCRIPTION_CONFIRMATION_MESSAGE",
                comment: "Update Subscription? Action sheet message, embeds {{Price}}"
            ),
            currencyString
        )
        let notNow = NSLocalizedString(
            "SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW",
            comment: "Sustainer view Not Now Action sheet button"
        )

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(.init(
            title: CommonStrings.continueButton,
            style: .default,
            handler: { [weak self] _ in
                self?.didTapToContinueMonthlyDonation()
            }
        ))
        actionSheet.addAction(.init(
            title: notNow,
            style: .cancel,
            handler: nil
        ))

        self.presentActionSheet(actionSheet)
    }

    private func didTapToCancelSubscription() {
        let title = NSLocalizedString(
            "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_TITLE",
            comment: "Confirm Cancellation? Action sheet title"
        )
        let message = NSLocalizedString(
            "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_MESSAGE",
            comment: "Confirm Cancellation? Action sheet message"
        )
        let confirm = NSLocalizedString(
            "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_CONFIRM",
            comment: "Confirm Cancellation? Action sheet confirm button"
        )
        let notNow = NSLocalizedString(
            "SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW",
            comment: "Sustainer view Not Now Action sheet button"
        )
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: confirm,
            style: .default,
            handler: { [weak self] _ in
                self?.didConfirmSubscriptionCancelation()
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: notNow,
            style: .cancel,
            handler: nil
        ))
        presentActionSheet(actionSheet)
    }

    private func didConfirmSubscriptionCancelation() {
        guard let subscriberID = state.monthly?.subscriberID else {
            owsFail("[Donations] No subscriber ID to cancel")
        }

        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            firstly {
                SubscriptionManager.cancelSubscription(for: subscriberID)
            }.done(on: .main) { [weak self] in
                modal.dismiss { [weak self] in
                    guard let self = self else { return }
                    self.onFinished(.monthlySubscriptionCancelled(
                        donateSheet: self,
                        toastText: NSLocalizedString(
                            "SUSTAINER_VIEW_SUBSCRIPTION_CANCELLED",
                            comment: "Toast indicating that the subscription has been cancelled"
                        )
                    ))
                }
            }.catch { error in
                modal.dismiss {}
                owsFailDebug("[Donations] Failed to cancel subscription \(error)")
            }
        }
    }

    // MARK: - Loading data

    private func loadAndUpdateState() {
        switch state.loadState {
        case .loading: return
        default: break
        }

        state = state.loading()

        loadState(currentState: state).done { [weak self] newState in
            self?.state = newState
        }
    }

    /// Try to load the data we need and put it into a new state.
    ///
    /// This requires both one-time and monthly data to load successfully.
    ///
    /// We could build this such that the state can be partially loaded. For
    /// example, users could interact with the one-time state while the monthly
    /// state continues to load, or if it fails. That'd make this screen
    /// resilient to partial failures, and faster to start using.
    ///
    /// However, this (1) significantly complicated the code when I tried it
    /// (2) will soon become less important, because the server plans to add a
    /// single endpoint that'll do most of this.
    private func loadState(currentState: State) -> Guarantee<State> {
        let oneTimeStatePromise = Self.loadOneTimeState()
        let monthlyStatePromise = Self.loadMonthlyState()

        return oneTimeStatePromise.then(on: .sharedUserInitiated) { oneTime in
            monthlyStatePromise.map { monthly in (oneTime, monthly) }
        }.then(on: .sharedUserInitiated) { [weak self] (oneTime: OneTimeData, monthly: MonthlyData) -> Promise<(oneTime: OneTimeData, monthly: MonthlyData)> in
            guard let self = self else { return Promise.value((oneTime, monthly)) }
            let oneTimeBadges = [oneTime.badge].compacted()
            let monthlyBadges = monthly.subscriptionLevels.map { $0.badge }
            let badges = oneTimeBadges + monthlyBadges
            let badgePromises = badges.map {
                self.profileManager.badgeStore.populateAssetsOnBadge($0)
            }
            return Promise.when(fulfilled: badgePromises).map { (oneTime, monthly) }
        }.then(on: .sharedUserInitiated) { (oneTime: OneTimeData, monthly: MonthlyData) in
            Guarantee.value(currentState.loaded(
                oneTimePresets: oneTime.presets,
                oneTimeBadge: oneTime.badge,
                monthlySubscriptionLevels: monthly.subscriptionLevels,
                currentMonthlySubscription: monthly.currentSubscription,
                subscriberID: monthly.subscriberID,
                previousMonthlySubscriptionCurrencyCode: monthly.previousSubscriptionCurrencyCode,
                locale: Locale.current
            ))
        }.recover(on: .sharedUserInitiated) { error -> Guarantee<State> in
            Logger.warn("[Donations] \(error)")
            owsFailDebugUnlessNetworkFailure(error)
            return Guarantee.value(currentState.loadFailed())
        }
    }

    private struct OneTimeData {
        let presets: [Currency.Code: DonationUtilities.Preset]
        let badge: ProfileBadge?
    }

    private static func loadOneTimeState() -> Promise<OneTimeData> {
        let profileBadgePromise: Promise<ProfileBadge?> = firstly {
            SubscriptionManager.getBoostBadge()
        }.map {
            Optional.some($0)
        }.recover { error in
            Logger.warn("[Donations] Failed to fetch boost badge \(error). Proceeding without it, as it is only cosmetic here")
            return Guarantee<ProfileBadge?>.value(nil)
        }

        return firstly(on: .sharedUserInitiated) {
            SubscriptionManager.getSuggestedBoostAmounts()
        }.then(on: .sharedUserInitiated) { presets in
            profileBadgePromise.map { badge in
                .init(presets: presets, badge: badge)
            }
        }
    }

    private struct MonthlyData {
        let subscriptionLevels: [SubscriptionLevel]
        let currentSubscription: Subscription?
        let subscriberID: Data?
        let previousSubscriptionCurrencyCode: Currency.Code?
    }

    private static func loadMonthlyState() -> Promise<MonthlyData> {
        let (subscriberID, previousCurrencyCode) = databaseStorage.read {(
            SubscriptionManager.getSubscriberID(transaction: $0),
            SubscriptionManager.getSubscriberCurrencyCode(transaction: $0)
        )}

        let currentSubscriptionPromise = DonationViewsUtil.loadCurrentSubscription(
            subscriberID: subscriberID
        )

        return firstly(on: .sharedUserInitiated) {
            DonationViewsUtil.loadSubscriptionLevels(badgeStore: self.profileManager.badgeStore)
        }.then(on: .sharedUserInitiated) { subscriptionLevels in
            currentSubscriptionPromise.map { currentSubscription in
                .init(
                    subscriptionLevels: subscriptionLevels,
                    currentSubscription: currentSubscription,
                    subscriberID: subscriberID,
                    previousSubscriptionCurrencyCode: previousCurrencyCode
                )
            }
        }
    }

    // MARK: - Top-level rendering

    private let scrollView = UIScrollView()

    private let stackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.alignment = .fill
        result.spacing = 24
        return result
    }()

    private func render(oldState: State?) {
        renderHeroView(oldState: oldState)
        renderBodyView(oldState: oldState)

        if oldState == nil {
            stackView.removeAllSubviews()
            stackView.addArrangedSubviews([heroView, bodyView])
        }

        view.backgroundColor = backgroundColor
    }

    // MARK: - Hero

    private lazy var avatarView: ConversationAvatarView = DonationViewsUtil.avatarView()

    private lazy var heroView: DonationHeroView = {
        let result = DonationHeroView(avatarView: avatarView)
        result.delegate = self
        return result
    }()

    private func renderHeroView(oldState: State?) {
        let selectedProfileBadge = state.selectedProfileBadge
        let shouldUpdateAvatar: Bool = (
            oldState == nil ||
            oldState?.selectedProfileBadge != selectedProfileBadge
        )
        guard shouldUpdateAvatar else { return }

        heroView.rerender()

        databaseStorage.read { [weak self] transaction in
            self?.avatarView.update(transaction) { config in
                guard let address = tsAccountManager.localAddress(with: transaction) else {
                    return
                }
                config.dataSource = .address(address)
                config.addBadgeIfApplicable = true
                config.fallbackBadge = selectedProfileBadge
            }
        }
    }

    // MARK: - Body

    private lazy var bodyView: UIStackView = Self.commonStack()

    private func renderBodyView(oldState: State?) {
        switch state.loadState {
        case .initializing, .loading, .loadFailed:
            // TODO: We should show a different state if the loading failed.
            renderLoadingBody(oldState: oldState)
        case let .loaded(oneTime, monthly):
            renderLoadedBody(
                oldState: oldState,
                donationMode: state.donationMode,
                oneTime: oneTime,
                monthly: monthly
            )
        }
    }

    private func renderLoadingBody(oldState: State?) {
        let wasPreviouslyLoading: Bool = {
            guard let oldState = oldState else { return false }
            switch oldState.loadState {
            case .initializing, .loading, .loadFailed:
                return true
            case .loaded:
                return false
            }
        }()
        if wasPreviouslyLoading { return }

        bodyView.removeAllSubviews()

        let spinner = loadingSpinnerView()
        bodyView.addArrangedSubview(spinner)
    }

    private func renderLoadedBody(
        oldState: State?,
        donationMode: DonationMode,
        oneTime: State.OneTimeState,
        monthly: State.MonthlyState
    ) {
        switch donationMode {
        case .oneTime:
            renderCurrencyPickerView(
                oldState: oldState,
                selectedCurrencyCode: oneTime.selectedCurrencyCode
            )
            renderOneTime(oldState: oldState, oneTime: oneTime)
        case .monthly:
            renderCurrencyPickerView(
                oldState: oldState,
                selectedCurrencyCode: monthly.selectedCurrencyCode
            )
            renderMonthly(oldState: oldState, monthly: monthly)
        }

        renderDonationModePickerView()

        let wasLoaded: Bool = {
            switch oldState?.loadState {
            case .loaded: return true
            default: return false
            }
        }()
        if !wasLoaded || oldState?.donationMode != state.donationMode {
            var subviews: [UIView] = [currencyPickerContainerView, donationModePickerView]
            switch donationMode {
            case .oneTime:
                subviews.append(oneTimeView)
            case .monthly:
                subviews.append(monthlyView)
            }

            bodyView.removeAllSubviews()
            bodyView.addArrangedSubviews(subviews)

            bodyView.setCustomSpacing(18, after: currencyPickerContainerView)

            // Switching modes causes animations to lose their anchors,
            // so we remove them.
            for subview in stackView.subviews {
                if subview is AnimationView {
                    subview.removeFromSuperview()
                }
            }
        }
    }

    // MARK: - Loading spinner

    private func loadingSpinnerView() -> UIView {
        let result: UIActivityIndicatorView
        if #available(iOS 13, *) {
            result = UIActivityIndicatorView(style: .medium)
        } else {
            result = UIActivityIndicatorView(style: .gray)
        }
        result.startAnimating()
        return result
    }

    // MARK: - Currency picker

    private var currencyPickerContainerView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.alignment = .fill
        return result
    }()

    private func renderCurrencyPickerView(
        oldState: State?,
        selectedCurrencyCode: Currency.Code
    ) {
        if
            oldState?.donationMode == state.donationMode,
            oldState?.selectedCurrencyCode == selectedCurrencyCode {
            return
        }

        let button = DonationCurrencyPickerButton(
            currentCurrencyCode: selectedCurrencyCode,
            hasLabel: false
        ) { [weak self] in
            guard let self = self else { return }

            let vc = CurrencyPickerViewController(
                dataSource: StripeCurrencyPickerDataSource(
                    currentCurrencyCode: selectedCurrencyCode,
                    supportedCurrencyCodes: self.state.supportedCurrencyCodes
                )
            ) { [weak self] currencyCode in
                guard let self = self else { return }
                self.state = self.state.selectCurrencyCode(currencyCode)
            }

            self.navigationController?.pushViewController(vc, animated: true)
        }

        currencyPickerContainerView.removeAllSubviews()
        currencyPickerContainerView.addArrangedSubview(button)
    }

    // MARK: - Donation mode picker

    private lazy var donationModePickerView: UISegmentedControl = {
        let picker = UISegmentedControl()
        picker.insertSegment(
            withTitle: NSLocalizedString(
                "DONATE_SCREEN_ONE_TIME_CHOICE",
                comment: "On the donation screen, you can choose between one-time and monthly donations. This is the text on the picker for one-time donations."
            ),
            at: DonationMode.oneTime.rawValue,
            animated: false
        )
        picker.insertSegment(
            withTitle: NSLocalizedString(
                "DONATE_SCREEN_MONTHLY_CHOICE",
                comment: "On the donation screen, you can choose between one-time and monthly donations. This is the text on the picker for one-time donations."
            ),
            at: DonationMode.monthly.rawValue,
            animated: false
        )
        picker.addTarget(self, action: #selector(didDonationModeChange), for: .valueChanged)
        return picker
    }()

    private func renderDonationModePickerView() {
        donationModePickerView.selectedSegmentIndex = state.donationMode.rawValue
    }

    // MARK: - One-time

    private struct OneTimePresetButton {
        let amount: FiatMoney
        let view: OWSFlatButton
    }

    private var oneTimePresetButtons = [OneTimePresetButton]()

    private lazy var oneTimePresetsView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.distribution = .fillEqually
        result.spacing = 20
        return result
    }()

    private lazy var oneTimeCustomAmountTextField: OneTimeDonationCustomAmountTextField = {
        guard let currencyCode = state.oneTime?.selectedCurrencyCode else {
            owsFail("[Donations] In the one-time view without a currency code")
        }

        let field = OneTimeDonationCustomAmountTextField(currencyCode: currencyCode)

        field.placeholder = NSLocalizedString(
            "BOOST_VIEW_CUSTOM_AMOUNT_PLACEHOLDER",
            comment: "Default text for the custom amount field of the boost view."
        )
        field.delegate = self
        field.accessibilityIdentifier = UIView.accessibilityIdentifier(
            in: self,
            name: "custom_amount_text_field"
        )

        field.layer.cornerRadius = Self.cornerRadius
        field.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth
        field.font = .ows_dynamicTypeBodyClamped

        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(didTapOneTimeCustomAmountTextField)
        )
        field.addGestureRecognizer(tap)

        return field
    }()

    private lazy var oneTimeContinueButton: OWSButton = {
        let button = OWSButton(title: CommonStrings.continueButton) { [weak self] in
            self?.didTapToContinueOneTimeDonation()
        }
        button.dimsWhenHighlighted = true
        button.dimsWhenDisabled = true
        button.layer.cornerRadius = 8
        button.backgroundColor = .ows_accentBlue
        button.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
        button.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        return button
    }()

    private lazy var oneTimeView: UIStackView = Self.commonStack()

    private func renderOneTime(oldState: State?, oneTime: State.OneTimeState) {
        renderOneTimePresetsView(oldState: oldState, oneTime: oneTime)
        renderOneTimeCustomAmountTextField(oneTime: oneTime)
        renderOneTimeContinueButton(oneTime: oneTime)

        switch oldState?.loadedDonationMode {
        case .oneTime:
            break
        default:
            oneTimeView.removeAllSubviews()
            oneTimeView.addArrangedSubviews([
                oneTimePresetsView,
                oneTimeCustomAmountTextField,
                oneTimeContinueButton
            ])
        }
    }

    private func initialRenderOfOneTimePresetRows(preset: DonationUtilities.Preset) {
        oneTimePresetsView.removeAllSubviews()

        var oneTimePresetButtons = [OneTimePresetButton]()

        for (rowIndex, amounts) in preset.amounts.chunked(by: 3).enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = UIDevice.current.isIPhone5OrShorter ? 8 : 14

            for (colIndex, amount) in amounts.enumerated() {
                let button = OWSFlatButton()
                button.setPressedBlock { [weak self] in
                    let animationNames = [
                        "boost_smile",
                        "boost_clap",
                        "boost_heart_eyes",
                        "boost_fire",
                        "boost_shock",
                        "boost_rockets"
                    ]
                    let animationIndex = (rowIndex * 3) + colIndex
                    self?.didSelectOneTimeAmount(
                        amount: amount,
                        animationAnchor: button,
                        animationName: animationNames[safe: animationIndex] ?? "boost_fire"
                    )
                }
                button.setBackgroundColors(
                    upColor: DonationViewsUtil.bubbleBackgroundColor,
                    downColor: DonationViewsUtil.bubbleBackgroundColor.withAlphaComponent(0.8)
                )
                button.setTitle(
                    title: DonationUtilities.format(money: amount),
                    font: .ows_regularFont(withSize: UIDevice.current.isIPhone5OrShorter ? 18 : 20),
                    titleColor: Theme.primaryTextColor
                )
                button.autoSetDimension(.height, toSize: 52, relation: .greaterThanOrEqual)
                button.enableMultilineLabel()
                button.layer.cornerRadius = Self.cornerRadius
                button.clipsToBounds = true
                button.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth

                row.addArrangedSubview(button)

                oneTimePresetButtons.append(.init(amount: amount, view: button))
            }

            oneTimePresetsView.addArrangedSubview(row)
        }

        self.oneTimePresetButtons = oneTimePresetButtons
    }

    private func renderOneTimePresetsView(oldState: State?, oneTime: State.OneTimeState) {
        if oldState?.loadedDonationMode != .oneTime || oldState?.oneTime?.selectedCurrencyCode != oneTime.selectedCurrencyCode {
            guard let preset = oneTime.selectedPreset else {
                owsFail("[Donations] It should be impossible to select a currency code without a preset")
            }
            initialRenderOfOneTimePresetRows(preset: preset)
        }

        let selectedPresetAmount: FiatMoney?
        switch oneTime.selectedAmount {
        case .nothingSelected, .choseCustomAmount:
            selectedPresetAmount = nil
        case let .selectedPreset(amount):
            selectedPresetAmount = amount
        }

        for button in oneTimePresetButtons {
            let selected = button.amount == selectedPresetAmount
            button.view.layer.borderColor = selected ? Self.selectedColor : Self.bubbleBackgroundColor
        }
    }

    private func renderOneTimeCustomAmountTextField(oneTime: State.OneTimeState) {
        switch oneTime.selectedAmount {
        case .nothingSelected, .selectedPreset:
            oneTimeCustomAmountTextField.text = nil
            oneTimeCustomAmountTextField.resignFirstResponder()
            oneTimeCustomAmountTextField.layer.borderColor = Self.bubbleBackgroundColor
        case let .choseCustomAmount(amount):
            oneTimeCustomAmountTextField.setCurrencyCode(amount.currencyCode)
            oneTimeCustomAmountTextField.layer.borderColor = Self.selectedColor
            scrollView.scrollIntoView(subview: oneTimeCustomAmountTextField)
        }

        oneTimeCustomAmountTextField.textColor = Theme.primaryTextColor
        oneTimeCustomAmountTextField.backgroundColor = DonationViewsUtil.bubbleBackgroundColor
    }

    private func renderOneTimeContinueButton(oneTime: State.OneTimeState) {
        oneTimeContinueButton.isEnabled = {
            switch oneTime.selectedAmount {
            case .nothingSelected:
                return false
            case .selectedPreset:
                return true
            case let .choseCustomAmount(amount):
                return amount.value > 0
            }
        }()
    }

    // MARK: - Monthly

    private var monthlySubscriptionLevelViews = [MonthlySubscriptionLevelView]()

    private lazy var monthlySubscriptionLevelsView: UIStackView = {
        let result = Self.commonStack()
        result.spacing = 10
        return result
    }()

    private lazy var monthlyButtonsView: UIStackView = {
        let result = Self.commonStack()
        result.spacing = 10
        return result
    }()

    private lazy var monthlyView: UIStackView = Self.commonStack()

    private func renderMonthly(oldState: State?, monthly: State.MonthlyState) {
        renderMonthlySubscriptionLevelsView(oldState: state, monthly: monthly)
        renderMonthlyButtonsView(monthly: monthly)

        switch oldState?.loadedDonationMode {
        case .monthly:
            break
        default:
            monthlyView.removeAllSubviews()
            monthlyView.addArrangedSubviews([
                monthlySubscriptionLevelsView,
                monthlyButtonsView
            ])
        }
    }

    private func initialRenderOfMonthlySubscriptionLevelViews(monthly: State.MonthlyState) {
        monthlySubscriptionLevelsView.removeAllSubviews()

        let animationNames = ["boost_fire", "boost_shock", "boost_rockets"]
        monthlySubscriptionLevelViews = monthly.subscriptionLevels
            .enumerated()
            .map { (index, subscriptionLevel) in
            MonthlySubscriptionLevelView(
                subscriptionLevel: subscriptionLevel,
                animationName: animationNames[safe: index] ?? "boost_fire"
            )
        }

        for view in monthlySubscriptionLevelViews {
            let tap = UITapGestureRecognizer(
                target: self,
                action: #selector(didTapMonthlySubscriptionLevelView)
            )
            view.addGestureRecognizer(tap)
            monthlySubscriptionLevelsView.addArrangedSubview(view)
        }
    }

    private func renderMonthlySubscriptionLevelsView(oldState: State?, monthly: State.MonthlyState) {
        let renderedSubscriptionLevels = monthlySubscriptionLevelViews.map(\.subscriptionLevel)
        if oldState?.monthly?.subscriptionLevels != renderedSubscriptionLevels {
            initialRenderOfMonthlySubscriptionLevelViews(monthly: monthly)
        }

        for subscriptionLevelView in monthlySubscriptionLevelViews {
            subscriptionLevelView.render(
                currencyCode: monthly.selectedCurrencyCode,
                currentSubscription: monthly.currentSubscription,
                selectedSubscriptionLevel: monthly.selectedSubscriptionLevel
            )
        }
    }

    private func renderMonthlyButtonsView(monthly: State.MonthlyState) {
        var buttons = [OWSButton]()

        if let currentSubscription = monthly.currentSubscription {
            let updateTitle = NSLocalizedString(
                "DONATE_SCREEN_UPDATE_MONTHLY_SUBSCRIPTION_BUTTON",
                comment: "On the donation screen, if you already have a subscription, you'll see a button to update your subscription. This is the text on that button."
            )
            let updateButton = OWSButton(title: updateTitle) { [weak self] in
                self?.didTapToUpdateMonthlyDonation()
            }
            updateButton.backgroundColor = .ows_accentBlue
            updateButton.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
            updateButton.isEnabled = {
                if currentSubscription.amount.currencyCode != monthly.selectedCurrencyCode {
                    return true
                }
                if
                    let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel,
                    currentSubscription.level != selectedSubscriptionLevel.level {
                    return true
                }
                return false
            }()
            buttons.append(updateButton)

            let cancelTitle = NSLocalizedString(
                "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION",
                comment: "Sustainer view Cancel Subscription button title"
            )
            let cancelButton = OWSButton(title: cancelTitle) { [weak self] in
                self?.didTapToCancelSubscription()
            }
            cancelButton.setTitleColor(Theme.accentBlueColor, for: .normal)
            cancelButton.dimsWhenHighlighted = true
            buttons.append(cancelButton)
        } else {
            let continueButton = OWSButton(title: CommonStrings.continueButton) { [weak self] in
                self?.didTapToContinueMonthlyDonation()
            }
            continueButton.layer.cornerRadius = 8
            continueButton.backgroundColor = .ows_accentBlue
            continueButton.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold

            buttons.append(continueButton)
        }

        for button in buttons {
            button.dimsWhenHighlighted = true
            button.dimsWhenDisabled = true
            button.layer.cornerRadius = 8
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.lineBreakMode = .byWordWrapping
            button.titleLabel?.textAlignment = .center
            button.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
        }

        monthlyButtonsView.removeAllSubviews()
        monthlyButtonsView.addArrangedSubviews(buttons)
    }
}

// MARK: - Donation hero delegate

extension DonateViewController: DonationHeroViewDelegate {
    func present(readMoreSheet: DonationReadMoreSheetViewController) {
        present(readMoreSheet, animated: true)
    }
}

// MARK: - One-Time donation custom amount field delegate

extension DonateViewController: OneTimeDonationCustomAmountTextFieldDelegate {
    func oneTimeDonationCustomAmountTextFieldStateDidChange(_ textField: OneTimeDonationCustomAmountTextField) {
        self.state = self.state.selectOneTimeAmount(.choseCustomAmount(amount: textField.amount))
    }
}

// MARK: - UIScrollView

fileprivate extension UIScrollView {
    /// Scroll a subview into view.
    ///
    /// Only meant for use on this screen. Your mileage may vary if used elsewhere.
    func scrollIntoView(subview: UIView) {
        guard let superview = subview.superview else { return }

        let currentVisibleTop = contentOffset.y
        let currentVisibleBottom = currentVisibleTop + bounds.height

        let subviewTop = superview.convert(subview.frame.topLeft, to: self).y
        let subviewBottom = superview.convert(subview.frame.bottomLeft, to: self).y

        let newY: CGFloat
        if subviewTop < currentVisibleTop {
            newY = subviewTop
        } else if subviewBottom > currentVisibleBottom {
            newY = subviewBottom - bounds.height
        } else {
            return
        }

        setContentOffset(.init(x: contentOffset.x, y: newY), animated: true)
    }
}
