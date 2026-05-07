//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

enum PaymentsSettingsMode: UInt, CustomStringConvertible {
    case inAppSettings
    case standalone

    // MARK: - CustomStringConvertible

    var description: String {
        switch self {
        case .inAppSettings:
            return "inAppSettings"
        case .standalone:
            return "standalone"
        }
    }
}

// MARK: -

class PaymentsSettingsViewController: OWSTableViewController2, PaymentsHistoryDataSourceDelegate,
    PaymentsViewPassphraseDelegate, PaymentsRestoreWalletDelegate
{

    private let appReadiness: AppReadinessSetter
    private let mode: PaymentsSettingsMode

    private let paymentsHistoryDataSource = PaymentsHistoryDataSource()

    fileprivate static let maxHistoryCount: Int = 4

    private let topHeaderStackView = {
        let result = UIStackView()
        result.axis = .vertical
        return result
    }()

    private var outdatedClientReminderView: ReminderView?

    private var observations = [NotificationCenter.Observer]()

    init(
        mode: PaymentsSettingsMode,
        appReadiness: AppReadinessSetter,
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

    deinit {
        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
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
        updateBalanceTimer = WeakTimer.scheduledTimer(
            timeInterval: updateInterval,
            target: self,
            userInfo: nil,
            repeats: true,
        ) { _ in
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
                    transaction: transaction,
                )
            }
        }
        set {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                Self.keyValueStore.setBool(
                    newValue,
                    key: Self.savePassphraseShownKey,
                    transaction: transaction,
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
                    transaction: transaction,
                )
            }
        }
        set {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                Self.keyValueStore.setBool(
                    newValue,
                    key: Self.savePassphraseHelpCardEnabledKey,
                    transaction: transaction,
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
            .cashOut,
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
            .cashOut,
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
                comment: "Label warning the user that they should update Signal to continue using payments.",
            ),
            actionTitle: OWSLocalizedString(
                "OUTDATED_PAYMENT_CLIENT_ACTION_TITLE",
                comment: "Label for action link when the user has an outdated payment client",
            ),
            tapAction: { [weak self] in self?.didTapOutdatedPaymentClientReminder() },
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

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_TITLE",
            comment: "Title for the 'payments settings' view in the app settings.",
        )

        view.backgroundColor = .Signal.groupedBackground

        if mode == .standalone {
            navigationItem.leftBarButtonItem = .doneButton { [weak self] in
                self?.didTapDismiss()
            }
        }

        addObservations()

        paymentsHistoryDataSource.delegate = self
    }

    private func updateNavbar() {
        guard SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled else {
            navigationItem.rightBarButtonItem = nil
            return
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: Theme.iconImage(.buttonMore),
            primaryAction: UIAction { [weak self] _ in
                self?.showSettingsActionSheet()
            },
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        updateNavbar()
    }

    override func viewDidAppear(_ animated: Bool) {
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isMovingFromParent, mode == .inAppSettings {
            PaymentUtils.markAllUnreadPaymentsAsReadWithSneakyTransaction()
        }

        stopUpdateBalanceTimer()
    }

    // MARK: - Notifications

    private func addObservations() {
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsConstants.arePaymentsEnabledDidChange,
        ) { [weak self] _ in
            self?.arePaymentsEnabledDidChange()
        })
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsConstants.isPaymentsVersionOutdatedDidChange,
        ) { [weak self] _ in
            self?.isPaymentsVersionOutdatedDidChange()
        })
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsImpl.currentPaymentBalanceDidChange,
        ) { [weak self] _ in
            self?.updateTableContents()
        })
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsCurrenciesImpl.paymentConversionRatesDidChange,
        ) { [weak self] _ in
            self?.updateTableContents()
        })
    }

    private func arePaymentsEnabledDidChange() {
        updateTableContents()
        updateNavbar()

        if !SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled {
            presentToast(text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_DISABLED_TOAST",
                comment: "Message indicating that payments have been disabled in the app settings.",
            ))
        }
    }

    private func isPaymentsVersionOutdatedDidChange() {
        guard UIApplication.shared.frontmostViewController == self else { return }
        if SSKEnvironment.shared.paymentsHelperRef.isPaymentsVersionOutdated {
            OWSActionSheets.showPaymentsOutdatedClientSheet(title: .updateRequired)
        }
    }

    private func updateTableContents() {
        let arePaymentsEnabled = SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled
        if arePaymentsEnabled {
            updateTableContentsEnabled()
        } else {
            updateTableContentsNotEnabled()
        }
    }

    // MARK: - Payments Enabled

    private func updateTableContentsEnabled() {
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
            actionBlock: nil,
        ))
        contents.add(headerSection)

        let historySection = OWSTableSection()
        configureHistorySection(historySection, paymentsHistoryDataSource: paymentsHistoryDataSource)
        contents.add(historySection)

        addHelpCards(
            contents: contents,
            helpCards: helpCardsForEnabled,
        )

        self.contents = contents
    }

    private func configureEnabledHeader(cell: UITableViewCell) {

        // 1. Balance.
        let balanceLabel = UILabel()
        balanceLabel.font = UIFont.systemFont(ofSize: 54)
        balanceLabel.textAlignment = .center
        balanceLabel.adjustsFontSizeToFitWidth = true

        let balanceLabelContainer = UIView.container()
        balanceLabelContainer.addSubview(balanceLabel)
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            balanceLabel.topAnchor.constraint(equalTo: balanceLabelContainer.topAnchor),
            balanceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: balanceLabelContainer.leadingAnchor),
            balanceLabel.centerXAnchor.constraint(equalTo: balanceLabelContainer.centerXAnchor),
            balanceLabel.bottomAnchor.constraint(equalTo: balanceLabelContainer.bottomAnchor),
        ])

        // 2. Conversion.
        let conversionRefreshButton = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapConversionRefresh()
            },
        )
        conversionRefreshButton.configuration?.image = UIImage(named: "refresh-20")
        conversionRefreshButton.configuration?.contentInsets = .init(hMargin: 12, vMargin: 4)
        conversionRefreshButton.tintColor = .Signal.label

        let conversionLabel = UILabel()
        conversionLabel.font = .dynamicTypeSubheadlineClamped
        conversionLabel.adjustsFontForContentSizeCategory = true
        conversionLabel.textColor = .Signal.secondaryLabel

        let conversionInfoButton = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCurrencyConversionInfo()
            },
        )
        conversionInfoButton.configuration?.image = UIImage(named: "info-20")
        conversionInfoButton.configuration?.contentInsets = .init(hMargin: 12, vMargin: 4)
        conversionInfoButton.tintColor = .Signal.secondaryLabel

        let conversionStack = UIStackView(arrangedSubviews: [
            conversionRefreshButton,
            conversionLabel,
            conversionInfoButton,
        ])
        conversionStack.axis = .horizontal
        conversionStack.alignment = .center

        let conversionStackContainer = UIView.container()
        conversionStackContainer.addSubview(conversionStack)
        conversionStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            conversionStack.topAnchor.constraint(equalTo: conversionStackContainer.topAnchor, constant: 8),
            conversionStack.leadingAnchor.constraint(greaterThanOrEqualTo: conversionStackContainer.leadingAnchor),
            conversionStack.centerXAnchor.constraint(equalTo: conversionStackContainer.centerXAnchor),
            conversionStack.bottomAnchor.constraint(equalTo: conversionStackContainer.bottomAnchor, constant: -44),
        ])

        if let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance {
            balanceLabel.attributedText = PaymentsFormat.attributedFormat(
                paymentAmount: paymentBalance.amount,
                isShortForm: false,
            )

            if let balanceConversionText = Self.buildBalanceConversionText(paymentBalance: paymentBalance) {
                conversionLabel.text = balanceConversionText
            } else {
                conversionStack.alpha = 0
            }
        } else {
            // Use an empty string to avoid jitter in layout between the
            // "pending balance" and "has balance" states.
            balanceLabel.text = " "

            let activityIndicator = UIActivityIndicatorView(style: .medium)
            balanceLabelContainer.addSubview(activityIndicator)
            activityIndicator.autoCenterInSuperview()
            activityIndicator.startAnimating()

            conversionStack.alpha = 0
        }

        // 3. Buttons.
        let addMoneyButton = buildHeaderButton(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ADD_MONEY",
                comment: "Label for 'add money' view in the payment settings.",
            ),
            iconName: "plus",
            action: UIAction { [weak self] _ in
                self?.didTapAddMoneyButton()
            },
        )
        let sendPaymentButton = buildHeaderButton(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_SEND_PAYMENT",
                comment: "Label for 'send payment' button in the payment settings.",
            ),
            iconName: "send-mob-24",
            action: UIAction { [weak self] _ in
                self?.didTapSendPaymentButton()
            },
        )
        let buttonStack = UIStackView(arrangedSubviews: [
            addMoneyButton,
            sendPaymentButton,
        ])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 16
        buttonStack.alignment = .fill
        buttonStack.distribution = .fillEqually

        let headerStack = OWSStackView(
            name: "headerStack",
            arrangedSubviews: [
                balanceLabelContainer,
                conversionStackContainer,
                buttonStack,
            ],
        )
        headerStack.axis = .vertical
        headerStack.alignment = .fill
        cell.contentView.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 24),
            headerStack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
            headerStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
        ])

        headerStack.addTapGesture {
            SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
            SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()
        }
    }

    private func buildHeaderButton(title: String, iconName: String, action: UIAction) -> UIButton {
        let button = UIButton(configuration: .bordered(), primaryAction: action)

        // background
        button.configuration?.baseBackgroundColor = .Signal.secondaryGroupedBackground

        // image
        button.configuration?.image = UIImage(named: iconName)

        // title
        button.configuration?.title = title
        button.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeCaption2Clamped)

        // layout
        button.configuration?.imagePlacement = .top
        button.configuration?.imagePadding = 6
        button.configuration?.contentInsets = .init(hMargin: 20, vMargin: 12)
        if #available(iOS 26, *) {
            button.configuration?.cornerStyle = .large
        } else {
            button.configuration?.cornerStyle = .medium
        }

        return button
    }

    private static func buildBalanceConversionText(paymentBalance: PaymentBalance) -> String? {
        let localCurrencyCode = SSKEnvironment.shared.paymentsCurrenciesRef.currentCurrencyCode
        guard let currencyConversionInfo = SSKEnvironment.shared.paymentsCurrenciesRef.conversionInfo(forCurrencyCode: localCurrencyCode) else {
            return nil
        }
        guard
            let fiatAmountString = PaymentsFormat.formatAsFiatCurrency(
                paymentAmount: paymentBalance.amount,
                currencyConversionInfo: currencyConversionInfo,
            )
        else {
            return nil
        }

        // NOTE: conversion freshness is different than the balance freshness.
        //
        // We format the conversion freshness date using the local locale.
        // We format the currency using the EN/US locale.
        //
        // It is sufficient to format as a time, currency conversions go stale in less than a day.
        let conversionFreshnessString = DateUtil.formatDateAsTime(currencyConversionInfo.conversionDate)
        let formatString = OWSLocalizedString(
            "SETTINGS_PAYMENTS_BALANCE_CONVERSION_FORMAT",
            comment: "Format string for the 'local balance converted into local currency' indicator. Embeds: {{ %1$@ the local balance in the local currency, %2$@ the local currency code, %3$@ the date the currency conversion rate was obtained. }}..",
        )
        return String.nonPluralLocalizedStringWithFormat(formatString, fiatAmountString, localCurrencyCode, conversionFreshnessString)
    }

    private func configureHistorySection(
        _ section: OWSTableSection,
        paymentsHistoryDataSource: PaymentsHistoryDataSource,
    ) {

        guard paymentsHistoryDataSource.hasItems else {
            section.hasBackground = false
            section.shouldDisableCellSelection = true
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()

                    let label = UILabel.explanationTextLabel(text: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_NO_ACTIVITY_INDICATOR",
                        comment: "Message indicating that there is no payment activity to display in the payment settings.",
                    ))
                    cell.contentView.addSubview(label)
                    label.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        label.topAnchor.constraint(
                            equalTo: cell.contentView.layoutMarginsGuide.topAnchor,
                            constant: 12,
                        ),
                        label.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                        label.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                        label.bottomAnchor.constraint(
                            equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor,
                            constant: -24,
                        ),
                    ])

                    return cell
                },
            ))
            return
        }

        section.headerTitle = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RECENT_PAYMENTS",
            comment: "Label for the 'recent payments' section in the payment settings.",
        )
        section.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + PaymentModelCell.separatorInsetLeading

        var hasMoreItems = false
        for (index, paymentItem) in paymentsHistoryDataSource.items.enumerated() {
            guard index < PaymentsSettingsViewController.maxHistoryCount else {
                hasMoreItems = true
                break
            }
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = PaymentModelCell()
                    cell.configure(paymentItem: paymentItem)
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.didTapPaymentItem(paymentItem: paymentItem)
                },
            ))
        }

        if hasMoreItems {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.selectionStyle = .none
                    cell.accessoryType = .disclosureIndicator

                    let label = UILabel()
                    label.text = CommonStrings.seeAllButton
                    label.font = .dynamicTypeBodyClamped
                    label.textColor = .Signal.label
                    cell.contentView.addSubview(label)
                    NSLayoutConstraint.activate([
                        label.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor, constant: 10),
                        label.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                        label.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                        label.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor, constant: -10),
                    ])

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.showPaymentsHistoryView()
                },
            ))
        }
    }

    // MARK: - Payments Disabled

    private func updateTableContentsNotEnabled() {
        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.shouldDisableCellSelection = true
        headerSection.add(OWSTableItem(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                self?.configureNotEnabledCell(cell)
                return cell
            },
        ))
        contents.add(headerSection)

        addHelpCards(
            contents: contents,
            helpCards: helpCardsForNotEnabled,
        )

        self.contents = contents
    }

    private func configureNotEnabledCell(_ cell: UITableViewCell) {
        let titleLabel = UILabel.title2Label(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_OPT_IN_TITLE",
            comment: "Title for the 'payments opt-in' view in the app settings.",
        ))
        titleLabel.font = UIFont.dynamicTypeHeadlineClamped

        let heroImageView = LottieAnimationView(name: "activate-payments")
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.autoSetDimension(.height, toSize: view.bounds.size.smallerAxis * 0.5)

        let bodyLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_OPT_IN_MESSAGE",
            comment: "Message for the 'payments opt-in' view in the app settings.",
        ))
        bodyLabel.font = .dynamicTypeSubheadlineClamped

        let buttonTitle = (
            SUIEnvironment.shared.paymentsRef.paymentsEntropy != nil
                ? OWSLocalizedString(
                    "SETTINGS_PAYMENTS_OPT_IN_REACTIVATE_BUTTON",
                    comment: "Label for 'activate' button in the 'payments opt-in' view in the app settings.",
                )
                : OWSLocalizedString(
                    "SETTINGS_PAYMENTS_OPT_IN_ACTIVATE_BUTTON",
                    comment: "Label for 'activate' button in the 'payments opt-in' view in the app settings.",
                ),
        )
        let activateButton = UIButton(
            configuration: .largePrimary(title: buttonTitle),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapEnablePaymentsButton()
            },
        )

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            heroImageView,
            bodyLabel,
            activateButton,
        ])

        if SUIEnvironment.shared.paymentsRef.paymentsEntropy == nil {
            let buttonTitle = OWSLocalizedString(
                "SETTINGS_PAYMENTS_RESTORE_PAYMENTS_BUTTON",
                comment: "Label for 'restore payments' button in the payments settings.",
            )
            let restorePaymentsButton = UIButton(
                configuration: .largeSecondary(title: buttonTitle),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapRestorePaymentsButton()
                },
            )
            stack.addArrangedSubview(restorePaymentsButton)
            stack.setCustomSpacing(12, after: activateButton)
        }

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 20
        stack.setCustomSpacing(24, after: titleLabel)
        cell.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Help Cards UI

    private func addHelpCards(
        contents: OWSTableContents,
        helpCards: [HelpCard],
    ) {
        for helpCard in helpCards {
            switch helpCard {
            case .saveRecoveryPhrase:
                contents.add(buildHelpCard(
                    helpCard: helpCard,
                    title: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_SAVE_PASSPHRASE_TITLE",
                        comment: "Title for the 'Save Passphrase' help card in the payments settings.",
                    ),
                    body: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_SAVE_PASSPHRASE_DESCRIPTION",
                        comment: "Description for the 'Save Passphrase' help card in the payments settings.",
                    ),
                    buttonText: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_SAVE_PASSPHRASE_BUTTON",
                        comment: "Label for button in the 'Save Passphrase' help card in the payments settings.",
                    ),
                    iconName: Theme.isDarkThemeEnabled
                        ? "restore-dark"
                        : "restore",
                    action: { [weak self] in
                        self?.didTapSavePassphraseCard()
                    },
                ))
            case .updatePin:
                contents.add(buildHelpCard(
                    helpCard: helpCard,
                    title: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_UPDATE_PIN_TITLE",
                        comment: "Title for the 'Update PIN' help card in the payments settings.",
                    ),
                    body: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_UPDATE_PIN_DESCRIPTION",
                        comment: "Description for the 'Update PIN' help card in the payments settings.",
                    ),
                    buttonText: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_UPDATE_PIN_BUTTON",
                        comment: "Label for button in the 'Update PIN' help card in the payments settings.",
                    ),
                    iconName: Theme.isDarkThemeEnabled
                        ? "update-pin-dark"
                        : "update-pin",
                    action: { [weak self] in
                        self?.didTapUpdatePinCard()
                    },
                ))
            case .aboutMobileCoin:
                contents.add(buildHelpCard(
                    helpCard: helpCard,
                    title: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_ABOUT_MOBILECOIN_TITLE",
                        comment: "Title for the 'About MobileCoin' help card in the payments settings.",
                    ),
                    body: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_ABOUT_MOBILECOIN_DESCRIPTION",
                        comment: "Description for the 'About MobileCoin' help card in the payments settings.",
                    ),
                    buttonText: CommonStrings.learnMore,
                    iconName: "about-mobilecoin",
                    action: { [weak self] in
                        self?.didTapAboutMobileCoinCard()
                    },
                ))
            case .addMoney:
                contents.add(buildHelpCard(
                    helpCard: helpCard,
                    title: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_ADDING_TO_YOUR_WALLET_TITLE",
                        comment: "Title for the 'Adding to your wallet' help card in the payments settings.",
                    ),
                    body: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_ADDING_TO_YOUR_WALLET_DESCRIPTION",
                        comment: "Description for the 'Adding to your wallet' help card in the payments settings.",
                    ),
                    buttonText: CommonStrings.learnMore,
                    iconName: "add-money",
                    action: { [weak self] in
                        self?.didTapAddingToYourWalletCard()
                    },
                ))
            case .cashOut:
                contents.add(buildHelpCard(
                    helpCard: helpCard,
                    title: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_CASHING_OUT_TITLE",
                        comment: "Title for the 'Cashing Out' help card in the payments settings.",
                    ),
                    body: OWSLocalizedString(
                        "SETTINGS_PAYMENTS_HELP_CARD_CASHING_OUT_DESCRIPTION",
                        comment: "Description for the 'Cashing Out' help card in the payments settings.",
                    ),
                    buttonText: CommonStrings.learnMore,
                    iconName: "cash-out",
                    action: { [weak self] in
                        self?.didTapCashingOutCoinCard()
                    },
                ))
            }
        }
    }

    private func buildHelpCard(
        helpCard: HelpCard,
        title: String,
        body: String,
        buttonText: String,
        iconName: String,
        action: @escaping (() -> Void),
    ) -> OWSTableSection {
        let section = OWSTableSection()
        section.add(OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self else { return OWSTableItem.newCell() }

                let titleLabel = UILabel()
                titleLabel.text = title
                titleLabel.textColor = .Signal.label
                titleLabel.font = UIFont.dynamicTypeHeadlineClamped
                titleLabel.adjustsFontForContentSizeCategory = true

                let bodyLabel = UILabel()
                bodyLabel.text = body
                bodyLabel.textColor = .Signal.secondaryLabel
                bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
                bodyLabel.adjustsFontForContentSizeCategory = true
                bodyLabel.numberOfLines = 0
                bodyLabel.lineBreakMode = .byWordWrapping

                let buttonLabel = UILabel()
                buttonLabel.text = buttonText
                buttonLabel.textColor = .Signal.accent
                buttonLabel.font = UIFont.dynamicTypeSubheadlineClamped

                let animationView = LottieAnimationView(name: iconName)
                animationView.contentMode = .scaleAspectFit
                animationView.autoSetDimensions(to: .square(80))

                let dismissButton = UIButton(
                    configuration: .gray(),
                    primaryAction: UIAction { [weak self] _ in
                        self?.dismissHelpCard(helpCard)
                    },
                )
                dismissButton.configuration?.baseBackgroundColor = .Signal.primaryFill
                dismissButton.configuration?.image = UIImage(named: "x-extra-small")
                dismissButton.configuration?.contentInsets = .init(margin: 4)
                dismissButton.configuration?.cornerStyle = .capsule

                let topStack = UIStackView(arrangedSubviews: [titleLabel, .hStretchingSpacer(), dismissButton])
                topStack.spacing = 16
                topStack.axis = .horizontal
                topStack.alignment = .top

                let middleStack = UIStackView(arrangedSubviews: [bodyLabel, animationView])
                middleStack.spacing = 16
                middleStack.axis = .horizontal
                middleStack.alignment = .center

                let bottomStack = UIStackView(arrangedSubviews: [buttonLabel])
                bottomStack.axis = .horizontal

                let verticalStack = UIStackView(arrangedSubviews: [topStack, middleStack, bottomStack])
                verticalStack.axis = .vertical
                verticalStack.spacing = 8
                verticalStack.alignment = .leading

                let cell = OWSTableItem.newCell()
                cell.contentView.addSubview(verticalStack)
                verticalStack.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(dismissButton)
                dismissButton.translatesAutoresizingMaskIntoConstraints = false

                NSLayoutConstraint.activate([
                    verticalStack.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                    verticalStack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    verticalStack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    verticalStack.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),

                    dismissButton.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                    dismissButton.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                ])

                return cell
            },
            actionBlock: action,
        ))

        return section
    }

    // MARK: -

    private func showSettingsActionSheet() {
        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_TRANSFER_TO_EXCHANGE",
                comment: "Label for the 'transfer to exchange' button in the payment settings.",
            ),
            style: .default,
        ) { [weak self] _ in
            self?.didTapTransferToExchangeButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_SET_CURRENCY",
                comment: "Title for the 'set currency' view in the app settings.",
            ),
            style: .default,
        ) { [weak self] _ in
            self?.didTapSetCurrencyButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS",
                comment: "Label for 'deactivate payments' button in the app settings.",
            ),
            style: .default,
        ) { [weak self] _ in
            self?.didTapDeactivatePaymentsButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_RECOVERY_PASSPHRASE",
                comment: "Label for 'view payments recovery passphrase' button in the app settings.",
            ),
            style: .default,
        ) { [weak self] _ in
            self?.didTapViewPaymentsPassphraseButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.help,
            style: .default,
        ) { [weak self] _ in
            self?.didTapHelpButton()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func showConfirmDeactivatePaymentsUI() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_TITLE",
                comment: "Title for the 'deactivate payments confirmation' UI in the payment settings.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_DESCRIPTION",
                comment: "Description for the 'deactivate payments confirmation' UI in the payment settings.",
            ),
        )

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.continueButton,
            style: .default,
        ) { [weak self] _ in
            self?.didTapConfirmDeactivatePaymentsButton()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didTapConversionRefresh() {
        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
        SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()
    }

    private func didTapCurrencyConversionInfo() {
        PaymentsSettingsViewController.showCurrencyConversionInfoAlert(fromViewController: self)
    }

    static func showCurrencyConversionInfoAlert(fromViewController: UIViewController) {
        let message = OWSLocalizedString(
            "SETTINGS_PAYMENTS_CURRENCY_CONVERSIONS_INFO_ALERT_MESSAGE",
            comment: "Message for the 'currency conversions info' alert.",
        )
        let actionSheet = ActionSheetController(title: nil, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.learnMore,
            style: .default,
            handler: { _ in
                CurrentAppContext().open(
                    URL.Support.Payments.currencyConversion,
                    completion: nil,
                )
            },
        ))
        actionSheet.addAction(OWSActionSheets.okayAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    // MARK: - Events

    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    private func didTapEnablePaymentsButton() {
        showEnablePaymentsConfirmUI()
    }

    private func showEnablePaymentsConfirmUI() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_TITLE",
                comment: "Title for the 'activate payments confirmation' UI in the payment settings.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_DESCRIPTION",
                comment: "Description for the 'activate payments confirmation' UI in the payment settings.",
            ),
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_AGREE",
                comment: "Label for the 'agree to payments terms' button in the 'activate payments confirmation' UI in the payment settings.",
            ),
            style: .default,
        ) { [weak self] _ in
            self?.enablePayments()
            self?.promptBiometryPaymentsLock()
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ACTIVATE_PAYMENTS_CONFIRM_VIEW_TERMS",
                comment: "Label for the 'view payments terms' button in the 'activate payments confirmation' UI in the payment settings.",
            ),
            style: .default,
        ) { _ in
            UIApplication.shared.open(
                URL(string: "https://www.mobilecoin.com/terms-of-use.html")!,
                options: [:],
                completionHandler: nil,
            )
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func enablePayments() {
        guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_CANNOT_ACTIVATE_PAYMENTS_KILL_SWITCH",
                comment: "Error message indicating that payments could not be activated because the feature is not currently available.",
            ))
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
        guard let view = PaymentsBiometryLockPromptViewController(deviceOwnerAuthenticationType: .current, delegate: nil) else {
            owsFailDebug("Unknown biometry type, cannot enable payments lock")
            return
        }
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    private func showPaymentsActivatedToast() {
        let toastText = OWSLocalizedString(
            "SETTINGS_PAYMENTS_OPT_IN_ACTIVATED_TOAST",
            comment: "Message shown when payments are activated in the 'payments opt-in' view in the app settings.",
        )
        self.presentToast(text: toastText)
    }

    private func didTapRestorePaymentsButton() {
        guard SUIEnvironment.shared.paymentsRef.paymentsEntropy == nil else {
            owsFailDebug("paymentsEntropy already set.")
            return
        }

        let view = PaymentsRestoreWalletSplashViewController(restoreWalletDelegate: self)
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    private func didTapSetCurrencyButton() {
        let view = CurrencyPickerViewController(
            dataSource: PaymentsCurrencyPickerDataSource(),
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
        let view = PaymentsViewPassphraseSplashViewController(
            passphrase: passphrase,
            style: style,
            viewPassphraseDelegate: self,
        )
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }

    private func didTapDeactivatePaymentsButton() {
        showConfirmDeactivatePaymentsUI()
    }

    private func didTapConfirmDeactivatePaymentsButton() {
        guard let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_CANNOT_DEACTIVATE_PAYMENTS_NO_BALANCE",
                comment: "Error message indicating that payments could not be deactivated because the current balance is unavailable.",
            ))
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

    private func didTapAddMoneyButton() {
        guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_CANNOT_TRANSFER_IN_KILL_SWITCH",
                comment: "Error message indicating that you cannot transfer into your payments wallet because the feature is not currently available.",
            ))
            return
        }
        let view = PaymentsTransferInViewController()
        let navigationController = OWSNavigationController(rootViewController: view)
        present(navigationController, animated: true, completion: nil)
    }

    private func didTapSendPaymentButton() {
        guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_CANNOT_SEND_PAYMENTS_KILL_SWITCH",
                comment: "Error message indicating that payments cannot be sent because the feature is not currently available.",
            ))
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

    private func didTapAboutMobileCoinCard() {
        CurrentAppContext().open(
            URL.Support.Payments.whichOnes,
            completion: nil,
        )
    }

    private func didTapAddingToYourWalletCard() {
        CurrentAppContext().open(
            URL.Support.Payments.transferFromExchange,
            completion: nil,
        )
    }

    private func didTapCashingOutCoinCard() {
        CurrentAppContext().open(
            URL.Support.Payments.transferToExchange,
            completion: nil,
        )
    }

    private func didTapUpdatePinCard() {
        guard let navigationController else {
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

    private func didTapSavePassphraseCard() {
        showPaymentsPassphraseUI(style: .fromHelpCard)
    }

    // MARK: - PaymentsHistoryDataSourceDelegate

    var recordType: PaymentsHistoryDataSource.RecordType {
        .all
    }

    var maxRecordCount: Int? {
        // Load an extra item so we can detect if there's more items
        // to render.
        Self.maxHistoryCount + 1
    }

    func didUpdateContent() {
        updateTableContents()
    }

    // MARK: - PaymentsViewPassphraseDelegate

    private static let hasReviewedPassphraseKey = "hasReviewedPassphrase"

    static func hasReviewedPassphraseWithSneakyTransaction() -> Bool {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            Self.keyValueStore.getBool(
                Self.hasReviewedPassphraseKey,
                defaultValue: false,
                transaction: transaction,
            )
        }
    }

    static func setHasReviewedPassphraseWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            Self.keyValueStore.setBool(
                true,
                key: Self.hasReviewedPassphraseKey,
                transaction: transaction,
            )
        }
    }

    func viewPassphraseDidComplete() {
        savePassphraseHelpCardEnabled = false
        if !Self.hasReviewedPassphraseWithSneakyTransaction() {
            Self.setHasReviewedPassphraseWithSneakyTransaction()

            presentToast(text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COMPLETE_TOAST",
                comment: "Message indicating that 'payments passphrase review' is complete.",
            ))
        }
    }

    func viewPassphraseDidCancel(viewController: PaymentsViewPassphraseSplashViewController) {
        viewController.dismiss(animated: true)
        if viewController.style.shouldShowHelpCardAfterCancel {
            clearHelpCardEnabledFromDismissedList()
            savePassphraseHelpCardEnabled = true
        }
    }

    // MARK: - PaymentsRestoreWalletDelegate

    func restoreWalletDidComplete() {
        presentToast(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_COMPLETE_TOAST",
            comment: "Message indicating that 'restore payments wallet' is complete.",
        ))
    }
}
