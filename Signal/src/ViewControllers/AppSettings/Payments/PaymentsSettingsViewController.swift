//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
public import SignalServiceKit
public import SignalUI

public enum PaymentsSettingsMode: UInt, CustomStringConvertible {
    case inAppSettings
    case standalone

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .inAppSettings:
            return "inAppSettings"
        case .standalone:
            return "standalone"
        }
    }
}

// MARK: -

final public class PaymentsSettingsViewController: OWSTableViewController2 {

    private let appReadiness: AppReadinessSetter
    private let mode: PaymentsSettingsMode

    private let paymentsHistoryDataSource = PaymentsHistoryDataSource()

    fileprivate static let maxHistoryCount: Int = 4

    private let topHeaderStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = 0
        return result
    }()

    private var outdatedClientReminderView: ReminderView?

    public init(
        mode: PaymentsSettingsMode,
        appReadiness: AppReadinessSetter
    ) {
        self.mode = mode
        self.appReadiness = appReadiness

        super.init()

        self.topHeader = topHeaderStackView

        // Add placeholder view to stackview so it always has an calculable height.
        let placeholderView = UIView()
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.heightAnchor.constraint(equalToConstant: 1).isActive = true
        topHeaderStackView.addArrangedSubview(placeholderView)
    }

    // MARK: - Update Balance Timer

    private var updateBalanceTimer: Timer?

    private func stopUpdateBalanceTimer() {
        updateBalanceTimer?.invalidate()
        updateBalanceTimer = nil
    }

    private func startUpdateBalanceTimer() {
        stopUpdateBalanceTimer()

        let updateInterval: TimeInterval = .second * 30
        self.updateBalanceTimer = WeakTimer.scheduledTimer(timeInterval: updateInterval,
                                                           target: self,
                                                           userInfo: nil,
                                                           repeats: true) { _ in
            Self.updateBalanceTimerDidFire()
        }
    }

    private static func updateBalanceTimerDidFire() {
        guard CurrentAppContext().isMainAppAndActive else {
            return
        }
        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
    }

    private var hasSignificantBalance: Bool {
        guard let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance else {
            return false
        }
        let significantPicoMob = 500 * Double(PaymentsConstants.picoMobPerMob)
        return Double(paymentBalance.amount.picoMob) >= significantPicoMob
    }

    private static let keyValueStore = KeyValueStore(collection: "PaymentSettings")

    private static let savePassphraseShownKey = "PaymentsSavePassphraseShown"
    private var savePassphraseShown: Bool {
        get {
            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                Self.keyValueStore.getBool(
                    Self.savePassphraseShownKey,
                    defaultValue: false,
                    transaction: transaction
                )
            }
        }
        set {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                Self.keyValueStore.setBool(
                    newValue,
                    key: Self.savePassphraseShownKey,
                    transaction: transaction
                )
            }
        }
    }

    private static let savePassphraseHelpCardEnabledKey = "PaymentsSavePassphraseHelpCardEnabled"
    private var savePassphraseHelpCardEnabled: Bool {
        get {
            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                Self.keyValueStore.getBool(
                    Self.savePassphraseHelpCardEnabledKey,
                    defaultValue: false,
                    transaction: transaction
                )
            }
        }
        set {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                Self.keyValueStore.setBool(
                    newValue,
                    key: Self.savePassphraseHelpCardEnabledKey,
                    transaction: transaction
                )
            }
            updateTableContents()
        }
    }

    private func showSavePaymentsPassphraseUIIfNeeded() {
        guard savePassphraseShown == false else { return }
        guard let amount = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance?.amount else { return }
        guard amount.picoMob > 0 else { return }
        savePassphraseShown = true
        showPaymentsPassphraseUI(style: .fromBalance)
    }

    private func clearHelpCardEnabledFromDismissedList() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            Self.helpCardStore.removeValue(forKey: HelpCard.saveRecoveryPhrase.rawValue, transaction: transaction)
        }
    }

    // MARK: - Help Cards

    private enum HelpCard: String, Equatable, CaseIterable {
        case saveRecoveryPhrase
        case updatePin
        case aboutMobileCoin
        case addMoney
        case cashOut
    }

    private var helpCardsForNotEnabled: [HelpCard] {
        let helpCards: [HelpCard] = [
            .aboutMobileCoin,
            .addMoney,
            .cashOut
        ]
        return filterDismissedHelpCards(helpCards)
    }

    private var helpCardsForEnabled: [HelpCard] {
        // Order matters as we build this list.
        var helpCards = OrderedSet<HelpCard>()

        if savePassphraseHelpCardEnabled {
            helpCards.append(.saveRecoveryPhrase)
        }

        if hasSignificantBalance {
            if !helpCards.contains(.saveRecoveryPhrase) {
                helpCards.append(.saveRecoveryPhrase)
            }

            let hasShortOrMissingPin: Bool = {
                guard let pinCode = SSKEnvironment.shared.ows2FAManagerRef.pinCodeWithSneakyTransaction else {
                    return true
                }
                let shortPinLength: UInt = 4
                return pinCode.count <= shortPinLength
            }()
            if hasShortOrMissingPin {
                helpCards.append(.updatePin)
            }
        } else {
            clearHelpCardEnabledFromDismissedList()
        }

        let defaultCards: [HelpCard] = [
            .aboutMobileCoin,
            .addMoney,
            .cashOut
        ]
        for card in defaultCards {
            helpCards.append(card)
        }
        return filterDismissedHelpCards(helpCards.orderedMembers)
    }

    private static let helpCardStore = KeyValueStore(collection: "paymentsHelpCardStore")

    private func filterDismissedHelpCards(_ helpCards: [HelpCard]) -> [HelpCard] {
        let dismissedKeys = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            Self.helpCardStore.allKeys(transaction: transaction)
        }
        return helpCards.filter { helpCard in !dismissedKeys.contains(helpCard.rawValue) }
    }

    private func dismissHelpCard(_ helpCard: HelpCard) {
        if helpCard == .saveRecoveryPhrase {
            showPaymentsPassphraseUI(style: .fromHelpCardDismiss)
            savePassphraseHelpCardEnabled = false
        }
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            Self.helpCardStore.setString(helpCard.rawValue, key: helpCard.rawValue, transaction: transaction)
        }
        updateTableContents()
    }

    // MARK: - Outdated Client Banner

    private func createOutdatedClientReminderView() {
        guard outdatedClientReminderView == nil else {
            return
        }

        let reminderView = ReminderView(
            style: .warning,
            text: OWSLocalizedString(
                "OUTDATED_PAYMENT_CLIENT_REMINDER_TEXT",
                comment: "Label warning the user that they should update Signal to continue using payments."
            ),
            actionTitle: OWSLocalizedString(
                "OUTDATED_PAYMENT_CLIENT_ACTION_TITLE",
                comment: "Label for action link when the user has an outdated payment client"
            ),
            tapAction: { [weak self] in self?.didTapOutdatedPaymentClientReminder() }
        )
        reminderView.accessibilityIdentifier = "outdatedClientView"
        topHeaderStackView.addArrangedSubview(reminderView)

        outdatedClientReminderView = reminderView
    }

    private func didTapOutdatedPaymentClientReminder() {
        let url = TSConstants.appStoreUrl
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: -

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_TITLE",
                                  comment: "Title for the 'payments settings' view in the app settings.")

        if mode == .standalone {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                               target: self,
                                                               action: #selector(didTapDismiss),
                                                               accessibilityIdentifier: "dismiss")
        }

        addListeners()

        updateTableContents()

        updateNavbar()

        paymentsHistoryDataSource.delegate = self
    }

    private func updateNavbar() {
        if SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: Theme.iconImage(.buttonMore),
                landscapeImagePhone: nil,
                style: .plain,
                target: self,
                action: #selector(didTapSettings)
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        updateNavbar()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
        SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()

        startUpdateBalanceTimer()
        let clientOutdated = SSKEnvironment.shared.paymentsHelperRef.isPaymentsVersionOutdated
        if clientOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .updateRequired)
            createOutdatedClientReminderView()
        }
        outdatedClientReminderView?.isHidden = !clientOutdated
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isMovingFromParent,
           mode == .inAppSettings {
            PaymentsViewUtils.markAllUnreadPaymentsAsReadWithSneakyTransaction()
        }

        stopUpdateBalanceTimer()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateTableContents()
    }

    private func addListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(arePaymentsEnabledDidChange),
            name: PaymentsConstants.arePaymentsEnabledDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(isPaymentsVersionOutdatedDidChange),
            name: PaymentsConstants.isPaymentsVersionOutdatedDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: PaymentsImpl.currentPaymentBalanceDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
            object: nil
        )
    }

    @objc
    private func arePaymentsEnabledDidChange() {
        updateTableContents()
        updateNavbar()

        if !SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled {
            presentToast(text: OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENTS_DISABLED_TOAST",
                                                 comment: "Message indicating that payments have been disabled in the app settings."))
        }
    }

    @objc
    private func isPaymentsVersionOutdatedDidChange() {
        guard UIApplication.shared.frontmostViewController == self else { return }
        if SSKEnvironment.shared.paymentsHelperRef.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .updateRequired)
        }
    }

    @objc
    private func updateTableContents() {
        AssertIsOnMainThread()

        let arePaymentsEnabled = SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled
        if arePaymentsEnabled {
            updateTableContentsEnabled()
        } else {
            updateTableContentsNotEnabled()
        }
    }

    private func updateTableContentsEnabled() {
        AssertIsOnMainThread()

        showSavePaymentsPassphraseUIIfNeeded()

        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.shouldDisableCellSelection = true
        headerSection.add(OWSTableItem(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                self?.configureEnabledHeader(cell: cell)
                return cell
            },
            actionBlock: nil
        ))
        contents.add(headerSection)

        let historySection = OWSTableSection()
        configureHistorySection(historySection, paymentsHistoryDataSource: paymentsHistoryDataSource)
        contents.add(historySection)

        addHelpCards(contents: contents,
                     helpCards: helpCardsForEnabled)

        self.contents = contents
    }

    private func configureEnabledHeader(cell: UITableViewCell) {
        let balanceLabel = UILabel()
        balanceLabel.font = UIFont.regularFont(ofSize: 54)
        balanceLabel.textAlignment = .center
        balanceLabel.adjustsFontSizeToFitWidth = true

        let balanceStack = UIStackView(arrangedSubviews: [ balanceLabel ])
        balanceStack.axis = .vertical
        balanceStack.alignment = .fill

        let conversionRefreshSize: CGFloat = 20
        let conversionRefreshIcon = UIImageView.withTemplateImageName("refresh-20",
                                                                      tintColor: Theme.primaryIconColor)
        conversionRefreshIcon.autoSetDimensions(to: .square(conversionRefreshSize))
        conversionRefreshIcon.isUserInteractionEnabled = true
        conversionRefreshIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapConversionRefresh)))

        let conversionLabel = UILabel()
        conversionLabel.font = UIFont.dynamicTypeSubheadlineClamped
        conversionLabel.textColor = Theme.secondaryTextAndIconColor

        let conversionInfoView = UIImageView()
        conversionInfoView.setTemplateImageName("info-compact", tintColor: Theme.secondaryTextAndIconColor)
        conversionInfoView.autoSetDimensions(to: .square(16))
        conversionInfoView.setCompressionResistanceHigh()

        let conversionStack1 = UIStackView(arrangedSubviews: [
            conversionRefreshIcon,
            conversionLabel,
            conversionInfoView
        ])
        conversionStack1.axis = .horizontal
        conversionStack1.alignment = .center
        conversionStack1.spacing = 12
        conversionStack1.isUserInteractionEnabled = true
        conversionStack1.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCurrencyConversionInfo)))

        let conversionStack2 = UIStackView(arrangedSubviews: [ conversionStack1 ])
        conversionStack2.axis = .vertical
        conversionStack2.alignment = .center

        func hideConversions() {
            conversionRefreshIcon.tintColor = .clear
            conversionLabel.text = " "
            conversionInfoView.tintColor = .clear
        }

        if let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance {
            balanceLabel.attributedText = PaymentsFormat.attributedFormat(paymentAmount: paymentBalance.amount,
                                                                          isShortForm: false)

            if let balanceConversionText = Self.buildBalanceConversionText(paymentBalance: paymentBalance) {
                conversionLabel.text = balanceConversionText
            } else {
                hideConversions()
            }
        } else {
            // Use an empty string to avoid jitter in layout between the
            // "pending balance" and "has balance" states.
            balanceLabel.text = " "

            let activityIndicator = UIActivityIndicatorView(style: .medium)
            balanceStack.addSubview(activityIndicator)
            activityIndicator.autoCenterInSuperview()
            activityIndicator.startAnimating()

            hideConversions()
        }

        let addMoneyButton = buildHeaderButton(title: OWSLocalizedString("SETTINGS_PAYMENTS_ADD_MONEY",
                                                                        comment: "Label for 'add money' view in the payment settings."),
                                               iconName: "plus",
                                               selector: #selector(didTapAddMoneyButton))
        let sendPaymentButton = buildHeaderButton(title: OWSLocalizedString("SETTINGS_PAYMENTS_SEND_PAYMENT",
                                                                           comment: "Label for 'send payment' button in the payment settings."),
                                                  iconName: "send-mob-24",
                                                  selector: #selector(didTapSendPaymentButton))
        let buttonStack = UIStackView(arrangedSubviews: [
            addMoneyButton,
            sendPaymentButton
        ])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .fill
        buttonStack.distribution = .fillEqually

        let headerStack = OWSStackView(name: "headerStack",
                                       arrangedSubviews: [
            balanceStack,
            UIView.spacer(withHeight: 8),
            conversionStack2,
            UIView.spacer(withHeight: 44),
            buttonStack
        ])
        headerStack.axis = .vertical
        headerStack.alignment = .fill
        headerStack.layoutMargins = .init(top: 30, left: 0, bottom: 8, right: 0)
        headerStack.isLayoutMarginsRelativeArrangement = true
        cell.contentView.addSubview(headerStack)
        headerStack.autoPinEdgesToSuperviewEdges()

        headerStack.addTapGesture {
            SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
            SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()
        }
    }

    private func buildHeaderButton(title: String, iconName: String, selector: Selector) -> UIView {

        let iconView = UIImageView.withTemplateImageName(iconName,
                                                         tintColor: Theme.primaryIconColor)
        iconView.autoSetDimensions(to: .square(24))

        let label = UILabel()
        label.text = title
        label.textColor = Theme.primaryTextColor
        label.font = .dynamicTypeCaption2Clamped

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            label
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.layoutMargins = UIEdgeInsets(top: 12, leading: 20, bottom: 6, trailing: 20)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.isUserInteractionEnabled = true
        stack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: selector))

        let backgroundView = UIView()
        backgroundView.backgroundColor = OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true)
        backgroundView.layer.cornerRadius = 10
        stack.addSubview(backgroundView)
        stack.sendSubviewToBack(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        return stack
    }

    private static func buildBalanceConversionText(paymentBalance: PaymentBalance) -> String? {
        let localCurrencyCode = SSKEnvironment.shared.paymentsCurrenciesRef.currentCurrencyCode
        guard let currencyConversionInfo = SSKEnvironment.shared.paymentsCurrenciesRef.conversionInfo(forCurrencyCode: localCurrencyCode)  else {
            return nil
        }
        guard let fiatAmountString = PaymentsFormat.formatAsFiatCurrency(paymentAmount: paymentBalance.amount,
                                                                       currencyConversionInfo: currencyConversionInfo) else {
            return nil
        }

        // NOTE: conversion freshness is different than the balance freshness.
        //
        // We format the conversion freshness date using the local locale.
        // We format the currency using the EN/US locale.
        //
        // It is sufficient to format as a time, currency conversions go stale in less than a day.
        let conversionFreshnessString = DateUtil.formatDateAsTime(currencyConversionInfo.conversionDate)
        let formatString = OWSLocalizedString("SETTINGS_PAYMENTS_BALANCE_CONVERSION_FORMAT",
                                             comment: "Format string for the 'local balance converted into local currency' indicator. Embeds: {{ %1$@ the local balance in the local currency, %2$@ the local currency code, %3$@ the date the currency conversion rate was obtained. }}..")
        return String(format: formatString, fiatAmountString, localCurrencyCode, conversionFreshnessString)
    }

    private func configureHistorySection(_ section: OWSTableSection,
                                         paymentsHistoryDataSource: PaymentsHistoryDataSource) {

        guard paymentsHistoryDataSource.hasItems else {
            section.hasBackground = false
            section.shouldDisableCellSelection = true
            section.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()

                let label = UILabel()
                label.text = OWSLocalizedString("SETTINGS_PAYMENTS_NO_ACTIVITY_INDICATOR",
                                               comment: "Message indicating that there is no payment activity to display in the payment settings.")
                label.textColor = Theme.secondaryTextAndIconColor
                label.font = UIFont.dynamicTypeBodyClamped
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.textAlignment = .center

                let stack = UIStackView(arrangedSubviews: [label])
                stack.axis = .vertical
                stack.alignment = .fill
                stack.layoutMargins = UIEdgeInsets(top: 10, leading: 0, bottom: 30, trailing: 0)
                stack.isLayoutMarginsRelativeArrangement = true

                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: nil))
            return
        }

        section.headerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_RECENT_PAYMENTS",
                                                comment: "Label for the 'recent payments' section in the payment settings.")

        section.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + PaymentModelCell.separatorInsetLeading

        var hasMoreItems = false
        for (index, paymentItem) in paymentsHistoryDataSource.items.enumerated() {
            guard index < PaymentsSettingsViewController.maxHistoryCount else {
                hasMoreItems = true
                break
            }
            section.add(OWSTableItem(customCellBlock: {
                let cell = PaymentModelCell()
                cell.configure(paymentItem: paymentItem)
                return cell
            },
            actionBlock: { [weak self] in
                self?.didTapPaymentItem(paymentItem: paymentItem)
            }))
        }

        if hasMoreItems {
            section.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none

                let label = UILabel()
                label.text = CommonStrings.seeAllButton
                label.font = .dynamicTypeBodyClamped
                label.textColor = Theme.primaryTextColor

                let stack = UIStackView(arrangedSubviews: [label])
                stack.axis = .vertical
                stack.alignment = .fill
                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()
                stack.layoutMargins = UIEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
                stack.isLayoutMarginsRelativeArrangement = true

                cell.accessoryType = .disclosureIndicator
                return cell
            },
            actionBlock: { [weak self] in
                self?.showPaymentsHistoryView()
            }))
        }
    }

    private func updateTableContentsNotEnabled() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.shouldDisableCellSelection = true
        headerSection.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            self?.configureNotEnabledCell(cell)
            return cell
        },
        actionBlock: nil))
        contents.add(headerSection)

        addHelpCards(contents: contents,
                     helpCards: helpCardsForNotEnabled)

        self.contents = contents
    }

    private func configureNotEnabledCell(_ cell: UITableViewCell) {

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_TITLE",
                                            comment: "Title for the 'payments opt-in' view in the app settings.")
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.dynamicTypeBodyClamped.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center

        let heroImageView = LottieAnimationView(name: "activate-payments")
        heroImageView.contentMode = .scaleAspectFit
        let viewSize = view.bounds.size
        let heroSize = min(viewSize.width, viewSize.height) * 0.5
        heroImageView.autoSetDimension(.height, toSize: heroSize)

        let bodyLabel = UILabel()
        bodyLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_MESSAGE",
                                           comment: "Message for the 'payments opt-in' view in the app settings.")
        bodyLabel.font = .dynamicTypeSubheadlineClamped
        bodyLabel.textColor = Theme.secondaryTextAndIconColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textAlignment = .center

        let buttonTitle = (SUIEnvironment.shared.paymentsRef.paymentsEntropy != nil
                            ? OWSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_REACTIVATE_BUTTON",
                                                comment: "Label for 'activate' button in the 'payments opt-in' view in the app settings.")
                            : OWSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_ACTIVATE_BUTTON",
                                                comment: "Label for 'activate' button in the 'payments opt-in' view in the app settings."))
        let activateButton = OWSFlatButton.button(title: buttonTitle,
                                                  font: UIFont.dynamicTypeBody.semibold(),
                                                  titleColor: .white,
                                                  backgroundColor: .ows_accentBlue,
                                                  target: self,
                                                  selector: #selector(didTapEnablePaymentsButton))
        activateButton.autoSetHeightUsingFont()

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 24),
            heroImageView,
            UIView.spacer(withHeight: 20),
            bodyLabel,
            UIView.spacer(withHeight: 20),
            activateButton
        ])

        if SUIEnvironment.shared.paymentsRef.paymentsEntropy == nil {
            let buttonTitle = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_PAYMENTS_BUTTON",
                                                comment: "Label for 'restore payments' button in the payments settings.")
            let restorePaymentsButton = OWSFlatButton.button(title: buttonTitle,
                                                             font: UIFont.dynamicTypeBody.semibold(),
                                                             titleColor: .ows_accentBlue,
                                                             backgroundColor: self.tableBackgroundColor,
                                                             target: self,
                                                             selector: #selector(didTapRestorePaymentsButton))
            restorePaymentsButton.autoSetHeightUsingFont()
            stack.addArrangedSubviews([
                UIView.spacer(withHeight: 8),
                restorePaymentsButton
            ])
        }

        stack.axis = .vertical
        stack.alignment = .fill
        stack.layoutMargins = UIEdgeInsets(top: 20, leading: 0, bottom: 32, trailing: 0)
        stack.isLayoutMarginsRelativeArrangement = true
        cell.contentView.addSubview(stack)
        stack.autoPinEdgesToSuperviewMargins()
    }

    private func addHelpCards(contents: OWSTableContents,
                              helpCards: [HelpCard]) {

        for helpCard in helpCards {
            switch helpCard {
            case .saveRecoveryPhrase:
                contents.add(buildHelpCard(helpCard: helpCard,
                                           title: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_SAVE_PASSPHRASE_TITLE",
                                                                     comment: "Title for the 'Save Passphrase' help card in the payments settings."),
                                           body: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_SAVE_PASSPHRASE_DESCRIPTION",
                                                                    comment: "Description for the 'Save Passphrase' help card in the payments settings."),
                                           buttonText: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_SAVE_PASSPHRASE_BUTTON",
                                                                          comment: "Label for button in the 'Save Passphrase' help card in the payments settings."),
                                           iconName: (Theme.isDarkThemeEnabled
                                                      ? "restore-dark"
                                                      : "restore"),
                                           selector: #selector(didTapSavePassphraseCard)))
            case .updatePin:
                contents.add(buildHelpCard(helpCard: helpCard,
                                           title: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_UPDATE_PIN_TITLE",
                                                                     comment: "Title for the 'Update PIN' help card in the payments settings."),
                                           body: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_UPDATE_PIN_DESCRIPTION",
                                                                    comment: "Description for the 'Update PIN' help card in the payments settings."),
                                           buttonText: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_UPDATE_PIN_BUTTON",
                                                                          comment: "Label for button in the 'Update PIN' help card in the payments settings."),
                                           iconName: (Theme.isDarkThemeEnabled
                                                      ? "update-pin-dark"
                                                      : "update-pin"),
                                           selector: #selector(didTapUpdatePinCard)))
            case .aboutMobileCoin:
                contents.add(buildHelpCard(helpCard: helpCard,
                                           title: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ABOUT_MOBILECOIN_TITLE",
                                                                     comment: "Title for the 'About MobileCoin' help card in the payments settings."),
                                           body: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ABOUT_MOBILECOIN_DESCRIPTION",
                                                                    comment: "Description for the 'About MobileCoin' help card in the payments settings."),
                                           buttonText: CommonStrings.learnMore,
                                           iconName: "about-mobilecoin",
                                           selector: #selector(didTapAboutMobileCoinCard)))
            case .addMoney:
                contents.add(buildHelpCard(helpCard: helpCard,
                                           title: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ADDING_TO_YOUR_WALLET_TITLE",
                                                                     comment: "Title for the 'Adding to your wallet' help card in the payments settings."),
                                           body: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_ADDING_TO_YOUR_WALLET_DESCRIPTION",
                                                                    comment: "Description for the 'Adding to your wallet' help card in the payments settings."),
                                           buttonText: CommonStrings.learnMore,
                                           iconName: "add-money",
                                           selector: #selector(didTapAddingToYourWalletCard)))
            case .cashOut:
                contents.add(buildHelpCard(helpCard: helpCard,
                                           title: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_CASHING_OUT_TITLE",
                                                                     comment: "Title for the 'Cashing Out' help card in the payments settings."),
                                           body: OWSLocalizedString("SETTINGS_PAYMENTS_HELP_CARD_CASHING_OUT_DESCRIPTION",
                                                                    comment: "Description for the 'Cashing Out' help card in the payments settings."),
                                           buttonText: CommonStrings.learnMore,
                                           iconName: "cash-out",
                                           selector: #selector(didTapCashingOutCoinCard)))
            }
        }
    }

    private func buildHelpCard(helpCard: HelpCard,
                               title: String,
                               body: String,
                               buttonText: String,
                               iconName: String,
                               selector: Selector) -> OWSTableSection {
        let section = OWSTableSection()

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: selector)

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else { return OWSTableItem.newCell() }

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.textColor = Theme.primaryTextColor
            titleLabel.font = UIFont.dynamicTypeBodyClamped.semibold()

            let bodyLabel = UILabel()
            bodyLabel.text = body
            bodyLabel.textColor = Theme.secondaryTextAndIconColor
            bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
            bodyLabel.numberOfLines = 0
            bodyLabel.lineBreakMode = .byWordWrapping

            let buttonLabel = UILabel()
            buttonLabel.text = buttonText
            buttonLabel.textColor = Theme.accentBlueColor
            buttonLabel.font = UIFont.dynamicTypeSubheadlineClamped

            let animationView = LottieAnimationView(name: iconName)
            animationView.contentMode = .scaleAspectFit
            animationView.autoSetDimensions(to: .square(80))

            let vStack = UIStackView(arrangedSubviews: [
                titleLabel,
                bodyLabel,
                buttonLabel
            ])
            vStack.axis = .vertical
            vStack.alignment = .leading
            vStack.spacing = 8

            let hStack = UIStackView(arrangedSubviews: [
                vStack,
                animationView
            ])
            hStack.axis = .horizontal
            hStack.alignment = .center
            hStack.spacing = 16

            let cell = OWSTableItem.newCell()
            cell.contentView.addSubview(hStack)
            hStack.autoPinEdgesToSuperviewMargins()

            let dismissIconView = UIImageView.withTemplateImage(Theme.iconImage(.buttonX),
                                                                tintColor: (Theme.isDarkThemeEnabled
                                                                            ? .ows_gray05
                                                                            : .ows_gray45))
            dismissIconView.autoSetDimensions(to: .square(10))
            let dismissButton = OWSLayerView.circleView()
            dismissButton.backgroundColor = (Theme.isDarkThemeEnabled
                                                ? .ows_gray65
                                                : .ows_gray02)
            dismissButton.addTapGesture { [weak self] in
                self?.dismissHelpCard(helpCard)
            }
            dismissButton.autoSetDimensions(to: .square(20))
            dismissButton.addSubview(dismissIconView)
            dismissIconView.autoCenterInSuperview()
            cell.contentView.addSubview(dismissButton)
            dismissButton.autoPinEdge(toSuperviewEdge: .top, withInset: 8)
            dismissButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 8)

            cell.isUserInteractionEnabled = true
            cell.addGestureRecognizer(tapGestureRecognizer)

            return cell
        },
        actionBlock: { [weak self] in
            self?.perform(selector)
        }))

        return section
    }

    // MARK: -

    private func showSettingsActionSheet() {
        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_TRANSFER_TO_EXCHANGE",
                comment: "Label for the 'transfer to exchange' button in the payment settings."
            ),
            style: .default
        ) { [weak self] _ in
            self?.didTapTransferToExchangeButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_SET_CURRENCY",
                comment: "Title for the 'set currency' view in the app settings."
            ),
            style: .default
        ) { [weak self] _ in
            self?.didTapSetCurrencyButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS",
                comment: "Label for 'deactivate payments' button in the app settings."
            ),
            style: .default
        ) { [weak self] _ in
            self?.didTapDeactivatePaymentsButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_RECOVERY_PASSPHRASE",
                comment: "Label for 'view payments recovery passphrase' button in the app settings."
            ),
            style: .default
        ) { [weak self] _ in
            self?.didTapViewPaymentsPassphraseButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.help,
            style: .default
        ) { [weak self] _ in
            self?.didTapHelpButton()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func showConfirmDeactivatePaymentsUI() {
        let actionSheet = ActionSheetController(title: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_TITLE",
                                                                         comment: "Title for the 'deactivate payments confirmation' UI in the payment settings."),
                                                message: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_DESCRIPTION",
                                                                           comment: "Description for the 'deactivate payments confirmation' UI in the payment settings."))

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.continueButton,
            style: .default
        ) { [weak self] _ in
            self?.didTapConfirmDeactivatePaymentsButton()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    @objc
    private func didTapConversionRefresh() {
        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
        SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()
    }

    @objc
    private func didTapCurrencyConversionInfo() {
        PaymentsSettingsViewController.showCurrencyConversionInfoAlert(fromViewController: self)
    }

    public static func showCurrencyConversionInfoAlert(fromViewController: UIViewController) {
        let message = OWSLocalizedString("SETTINGS_PAYMENTS_CURRENCY_CONVERSIONS_INFO_ALERT_MESSAGE",
                                        comment: "Message for the 'currency conversions info' alert.")
        let actionSheet = ActionSheetController(title: nil, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.learnMore,
            style: .default,
            handler: { _ in
                CurrentAppContext().open(
                    URL.Support.Payments.currencyConversion,
                    completion: nil
                )
            }
        ))
        actionSheet.addAction(OWSActionSheets.okayAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    // MARK: - Events

    @objc
    func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func didTapEnablePaymentsButton(_ sender: UIButton) {
        AssertIsOnMainThread()

        showEnablePaymentsConfirmUI()
    }

    private func showEnablePaymentsConfirmUI() {
        AssertIsOnMainThread()

        let actionSheet = ActionSheetController(title: OWSLocalizedString("SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_TITLE",
                                                                         comment: "Title for the 'activate payments confirmation' UI in the payment settings."),
                                                message: OWSLocalizedString("SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_DESCRIPTION",
                                                                           comment: "Description for the 'activate payments confirmation' UI in the payment settings."))

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_AGREE",
                comment: "Label for the 'agree to payments terms' button in the 'activate payments confirmation' UI in the payment settings."
            ),
            style: .default
        ) { [weak self] _ in
            self?.enablePayments()
            self?.promptBiometryPaymentsLock()
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_VIEW_TERMS",
                comment: "Label for the 'view payments terms' button in the 'activate payments confirmation' UI in the payment settings."
            ),
            style: .default
        ) { _ in
            UIApplication.shared.open(
                URL(string: "https://www.mobilecoin.com/terms-of-use.html")!,
                options: [:],
                completionHandler: nil
            )
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func enablePayments() {
        AssertIsOnMainThread()

        guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_CANNOT_ACTIVATE_PAYMENTS_KILL_SWITCH",
                                                                      comment: "Error message indicating that payments could not be activated because the feature is not currently available."))
            return
        }

        if SSKEnvironment.shared.paymentsHelperRef.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .updateRequired)
            return
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            SSKEnvironment.shared.paymentsHelperRef.enablePayments(transaction: transaction)

            transaction.addSyncCompletion {
                Task { @MainActor in
                    self.showPaymentsActivatedToast()
                }
            }
        }
    }

    private func promptBiometryPaymentsLock() {
        AssertIsOnMainThread()

        guard let view = PaymentsBiometryLockPromptViewController(deviceOwnerAuthenticationType: .current, delegate: nil) else {
            owsFailDebug("Unknown biometry type, cannot enable payments lock")
            return
        }
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    private func showPaymentsActivatedToast() {
        AssertIsOnMainThread()
        let toastText = OWSLocalizedString("SETTINGS_PAYMENTS_OPT_IN_ACTIVATED_TOAST",
                                          comment: "Message shown when payments are activated in the 'payments opt-in' view in the app settings.")
        self.presentToast(text: toastText)
    }

    @objc
    func didTapRestorePaymentsButton() {
        AssertIsOnMainThread()

        guard SUIEnvironment.shared.paymentsRef.paymentsEntropy == nil else {
            owsFailDebug("paymentsEntropy already set.")
            return
        }

        let view = PaymentsRestoreWalletSplashViewController(restoreWalletDelegate: self)
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    @objc
    func didTapSettings() {
        showSettingsActionSheet()
    }

    private func didTapSetCurrencyButton() {
        let view = CurrencyPickerViewController(
            dataSource: PaymentsCurrencyPickerDataSource()
        ) { currencyCode in
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.paymentsCurrenciesRef.setCurrentCurrencyCode(currencyCode, transaction: transaction)
            }
        }
        navigationController?.pushViewController(view, animated: true)
    }

    private func didTapViewPaymentsPassphraseButton() {
        if Self.hasReviewedPassphraseWithSneakyTransaction() {
            showPaymentsPassphraseUI(style: .reviewed)
        } else {
            showPaymentsPassphraseUI(style: .view)
        }
    }

    private func showPaymentsPassphraseUI(style: PaymentsViewPassphraseSplashViewController.Style) {
        guard let passphrase = SUIEnvironment.shared.paymentsSwiftRef.passphrase else {
            owsFailDebug("Missing passphrase.")
            return
        }
        let view = PaymentsViewPassphraseSplashViewController(passphrase: passphrase,
                                                              style: style,
                                                              viewPassphraseDelegate: self)
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    private func didTapDeactivatePaymentsButton() {
        showConfirmDeactivatePaymentsUI()
    }

    private func didTapConfirmDeactivatePaymentsButton() {
        guard let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_CANNOT_DEACTIVATE_PAYMENTS_NO_BALANCE",
                                                                      comment: "Error message indicating that payments could not be deactivated because the current balance is unavailable."))
            return
        }
        guard paymentBalance.amount.picoMob > 0 else {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.paymentsHelperRef.disablePayments(transaction: transaction)
            }
            return
        }
        let vc = PaymentsDeactivateViewController(paymentBalance: paymentBalance)
        let navigationVC = OWSNavigationController(rootViewController: vc)
        present(navigationVC, animated: true)
    }

    private func didTapHelpButton() {
        let view = ContactSupportViewController()
        view.selectedFilter = .payments
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
     }

    private func didTapTransferToExchangeButton() {
        if SSKEnvironment.shared.paymentsHelperRef.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .updateRequired)
            return
        }
        let view = PaymentsTransferOutViewController(transferAmount: nil)
        let navigationController = OWSNavigationController(rootViewController: view)
        present(navigationController, animated: true, completion: nil)
    }

    private func showPaymentsHistoryView() {
        let view = PaymentsHistoryViewController()
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    func didTapAddMoneyButton(sender: UIGestureRecognizer) {
        guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_CANNOT_TRANSFER_IN_KILL_SWITCH",
                                                                      comment: "Error message indicating that you cannot transfer into your payments wallet because the feature is not currently available."))
            return
        }
        let view = PaymentsTransferInViewController()
        let navigationController = OWSNavigationController(rootViewController: view)
        present(navigationController, animated: true, completion: nil)
    }

    @objc
    func didTapSendPaymentButton(sender: UIGestureRecognizer) {
        guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_CANNOT_SEND_PAYMENTS_KILL_SWITCH",
                                                                      comment: "Error message indicating that payments cannot be sent because the feature is not currently available."))
            return
        }

        if SSKEnvironment.shared.paymentsHelperRef.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .updateRequired)
            return
        }

        PaymentsSendRecipientViewController.presentAsFormSheet(fromViewController: self, isOutgoingTransfer: false)
    }

    private func didTapPaymentItem(paymentItem: PaymentsHistoryItem) {
        let view = PaymentsDetailViewController(paymentItem: paymentItem)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    private func didTapAboutMobileCoinCard() {
        CurrentAppContext().open(
            URL.Support.Payments.whichOnes,
            completion: nil
        )
    }

    @objc
    private func didTapAddingToYourWalletCard() {
        CurrentAppContext().open(
            URL.Support.Payments.transferFromExchange,
            completion: nil
        )
    }

    @objc
    private func didTapCashingOutCoinCard() {
        CurrentAppContext().open(
            URL.Support.Payments.transferToExchange,
            completion: nil
        )
    }

    @objc
    private func didTapUpdatePinCard() {
        guard let navigationController = self.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        switch mode {
        case .inAppSettings:
            navigationController.popViewController(animated: true) { [appReadiness] in
                let accountSettingsView = AccountSettingsViewController(appReadiness: appReadiness)
                navigationController.pushViewController(accountSettingsView, animated: true)
            }
        case .standalone:
            let accountSettingsView = AccountSettingsViewController(appReadiness: appReadiness)
            navigationController.pushViewController(accountSettingsView, animated: true)
        }
    }

    @objc
    private func didTapSavePassphraseCard() {
        showPaymentsPassphraseUI(style: .fromHelpCard)
    }
}

// MARK: -

extension PaymentsSettingsViewController: PaymentsHistoryDataSourceDelegate {
    var recordType: PaymentsHistoryDataSource.RecordType {
        .all
    }

    var maxRecordCount: Int? {
        // Load an extra item so we can detect if there's more items
        // to render.
        Self.maxHistoryCount + 1
    }

    func didUpdateContent() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}

// MARK: -

extension PaymentsSettingsViewController: PaymentsViewPassphraseDelegate {

    private static let hasReviewedPassphraseKey = "hasReviewedPassphrase"

    public static func hasReviewedPassphraseWithSneakyTransaction() -> Bool {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            Self.keyValueStore.getBool(Self.hasReviewedPassphraseKey,
                                       defaultValue: false,
                                       transaction: transaction)
        }
    }

    public static func setHasReviewedPassphraseWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            Self.keyValueStore.setBool(true,
                                       key: Self.hasReviewedPassphraseKey,
                                       transaction: transaction)
        }
    }

    public func viewPassphraseDidComplete() {
        self.savePassphraseHelpCardEnabled = false
        if !Self.hasReviewedPassphraseWithSneakyTransaction() {
            Self.setHasReviewedPassphraseWithSneakyTransaction()

            presentToast(text: OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COMPLETE_TOAST",
                                                 comment: "Message indicating that 'payments passphrase review' is complete."))
        }
    }

    public func viewPassphraseDidCancel(viewController: PaymentsViewPassphraseSplashViewController) {
        viewController.dismiss(animated: true)
        if viewController.style.shouldShowHelpCardAfterCancel {
            self.clearHelpCardEnabledFromDismissedList()
            self.savePassphraseHelpCardEnabled = true
        }
    }
}

// MARK: -

extension PaymentsSettingsViewController: PaymentsRestoreWalletDelegate {

    public func restoreWalletDidComplete() {
        presentToast(text: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_COMPLETE_TOAST",
                                             comment: "Message indicating that 'restore payments wallet' is complete."))
    }
}
