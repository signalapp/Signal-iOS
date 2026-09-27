//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
final class LinkedDeviceBackupSettingsViewController: OWSTableViewController2 {

    fileprivate enum DisplayTier {
        case free(mediaDays: UInt64)
        case paid
        case disabled
    }

    fileprivate enum LastBackupState {
        case loading
        case loaded(Date)
        case unavailable
    }

    fileprivate struct PaidSubscription {
        let price: FiatMoney
        let endOfCurrentPeriod: Date
        let isCanceled: Bool
    }

    fileprivate enum SubscriptionState {
        case loading
        case loaded(PaidSubscription)
        case paidButFreeForTesters
        case notFound
        case unavailable
    }

    private static let logger = PrefixedLogger(prefix: "[Backups]")

    private static let learnMoreURL = URL(string: "https://support.signal.org/hc/articles/360007059752-Backup-and-Restore-Messages")!

    private enum Strings {
        static var manageOrUpgradeOnPrimaryFooter: String {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LINKED_DEVICE_MANAGE_ON_PRIMARY_FOOTER",
                comment: "Note on the linked-device Backups screen explaining that the Backups subscription can only be managed on the user's primary device.",
            )
        }

        static var manageOrCancelOnPrimaryFooter: String {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LINKED_DEVICE_MANAGE_ON_PRIMARY_FOOTER_PAID",
                comment: "Note on the linked-device Backups screen, shown on the paid tier, explaining that the Backups subscription can only be managed on the user's primary device.",
            )
        }

        static var subscriptionNotFound: String {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LINKED_DEVICE_SUBSCRIPTION_NOT_FOUND",
                comment: "Message on the linked-device Backups screen, shown when the user's paid subscription can't be found, prompting them to renew.",
            )
        }

        static var noBackupFooter: String {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LINKED_DEVICE_NO_BACKUP_FOOTER",
                comment: "Body text on the linked-device Backups screen, shown when Backups aren't set up, explaining the feature and that it can be enabled on the user's primary device.",
            )
        }
    }

    private let currentDisplayTier: () -> DisplayTier

    private let loadLastBackupDate: () async -> Date?

    private let loadSubscription: () async -> SubscriptionState

    private var lastBackupState: LastBackupState = .loading
    private var lastBackupFetchTask: Task<Void, Never>?

    private var subscriptionState: SubscriptionState = .loading
    private var subscriptionFetchTask: Task<Void, Never>?

    private let localFileBackupsStore: LocalFileBackupStore
    private let db: DB

    override convenience init() {
        self.init(
            localFileBackupsStore: LocalFileBackupStore(),
            db: DependenciesBridge.shared.db,
        )
    }

    init(localFileBackupsStore: LocalFileBackupStore, db: DB) {
        self.currentDisplayTier = Self.currentDisplayTierFromDatabase
        self.loadLastBackupDate = Self.loadLastBackupDateFromCDN
        self.loadSubscription = Self.loadSubscriptionFromServer

        self.localFileBackupsStore = localFileBackupsStore
        self.db = db

        super.init()
    }

    deinit {
        lastBackupFetchTask?.cancel()
        subscriptionFetchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = BackupSettingsView.Strings.title
        OWSTableViewController2.removeBackButtonText(viewController: self)

        updateTableContents()

        switch currentDisplayTier() {
        case .free:
            fetchLastBackupDate()
        case .paid:
            fetchLastBackupDate()
            fetchSubscription()
        case .disabled:
            break
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    private static func currentDisplayTierFromDatabase() -> DisplayTier {
        let db = DependenciesBridge.shared.db
        let backupPlanManager = DependenciesBridge.shared.backupPlanManager
        let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager
        return db.read { tx in
            switch backupPlanManager.backupPlan(tx: tx) {
            case .free:
                .free(mediaDays: subscriptionConfigManager.backupConfigurationOrDefault(tx: tx).freeTierMediaDays)
            case .paid, .paidExpiringSoon, .paidAsTester:
                .paid
            case .disabled, .disabling:
                .disabled
            }
        }
    }

    @MainActor
    private func updateTableContents() {
        let contents = OWSTableContents()
        let displayTier = currentDisplayTier()

        let heroSection = OWSTableSection()
        heroSection.add(OWSTableItem(customCellBlock: { [weak self] in
            self?.heroCell(displayTier: displayTier) ?? UITableViewCell()
        }))
        contents.add(heroSection)

        switch displayTier {
        case .free, .paid:
            if let detailsSection = backupDetailsSection() {
                contents.add(detailsSection)
            }
        case .disabled:
            break
        }

        let onDeviceSection = OWSTableSection()
        onDeviceSection.customHeaderView = buildOtherWaysHeaderView()
        onDeviceSection.footerTitle = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_ON_DEVICE_BACKUPS_FOOTER",
            comment: "Footer text below the On-Device Backups row on the Backups settings landing page.",
        )
        onDeviceSection.add(buildOnDeviceBackupsItem())
        contents.add(onDeviceSection)

        self.contents = contents
    }

    private func heroCell(displayTier: DisplayTier) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none

        let labelStack = UIStackView()
        labelStack.axis = .vertical
        labelStack.spacing = 8

        let iconResource: ImageResource
        switch displayTier {
        case .free(let mediaDays):
            iconResource = .backupsSubscribed
            labelStack.addArrangedSubview(noteLabel(text: BackupSettingsView.Strings.freePlanHeader(mediaDays: mediaDays)))
            labelStack.addArrangedSubview(valueLabel(BackupSettingsView.Strings.freePlanDescription))
            labelStack.addArrangedSubview(noteLabel(text: Strings.manageOrUpgradeOnPrimaryFooter))
        case .paid:
            iconResource = addPaidHeroContent(to: labelStack)
        case .disabled:
            iconResource = .backupsLogo
            labelStack.addArrangedSubview(valueLabel(OWSLocalizedString(
                "BACKUP_ONBOARDING_INTRO_TITLE",
                comment: "Title for a view introducing Backups during an onboarding flow.",
            )))
            labelStack.addArrangedSubview(noBackupNoteView())
        }

        let iconImageView = UIImageView(image: UIImage(resource: iconResource))
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.autoSetDimensions(to: CGSize(square: 64))
        iconImageView.setContentHuggingHorizontalHigh()
        iconImageView.setCompressionResistanceHorizontalHigh()

        let hStack = UIStackView(arrangedSubviews: [labelStack, iconImageView])
        hStack.axis = .horizontal
        hStack.alignment = .top
        hStack.spacing = 16

        cell.contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges(with: .init(margin: 20))

        return cell
    }

    private func addPaidHeroContent(to stackView: UIStackView) -> ImageResource {
        var paidPlanHeader: UIView { noteLabel(text: BackupSettingsView.Strings.paidPlanHeader) }

        switch subscriptionState {
        case .notFound:
            stackView.addArrangedSubview(valueLabel(Strings.subscriptionNotFound))
            stackView.addArrangedSubview(noteLabel(text: Strings.manageOrUpgradeOnPrimaryFooter))
            return .backupsLogoWarningBadged
        case .loading, .unavailable:
            stackView.addArrangedSubview(paidPlanHeader)
        case .paidButFreeForTesters:
            stackView.addArrangedSubview(paidPlanHeader)
            stackView.addArrangedSubview(valueLabel(BackupSettingsView.Strings.paidPlanFreeForTestersText))
        case .loaded(let subscription):
            stackView.addArrangedSubview(paidPlanHeader)
            if subscription.isCanceled {
                let canceledLabel = UILabel()
                canceledLabel.numberOfLines = 0
                canceledLabel.font = .dynamicTypeHeadlineClamped.semibold()
                canceledLabel.textColor = .Signal.red
                canceledLabel.text = BackupSettingsView.Strings.paidPlanCanceledText
                stackView.addArrangedSubview(canceledLabel)
                stackView.setCustomSpacing(0, after: canceledLabel)
                stackView.addArrangedSubview(valueLabel(BackupSettingsView.Strings.paidPlanExpirationText(subscription.endOfCurrentPeriod)))
            } else {
                let price = valueLabel(BackupSettingsView.Strings.paidPlanPriceText(subscription.price))
                stackView.addArrangedSubview(price)
                stackView.setCustomSpacing(0, after: price)
                stackView.addArrangedSubview(valueLabel(BackupSettingsView.Strings.paidPlanRenewalText(subscription.endOfCurrentPeriod)))
            }
        }

        stackView.addArrangedSubview(noteLabel(text: Strings.manageOrCancelOnPrimaryFooter))
        return .backupsSubscribed
    }

    private func valueLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .dynamicTypeBody
        label.textColor = UIColor.Signal.label
        label.text = text
        return label
    }

    private func noteLabel(text: String) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = UIColor.Signal.secondaryLabel
        label.text = text
        return label
    }

    private func noBackupNoteView() -> UIView {
        let textView = LinkingTextView()

        let font = UIFont.dynamicTypeSubheadlineClamped
        let attributedTitle = NSAttributedString.composed(of: [
            Strings.noBackupFooter,
            " ",
            CommonStrings.learnMore.styled(
                with: .link(Self.learnMoreURL),
                .font(font.semibold()),
            ),
        ]).styled(with: .font(font), .color(UIColor.Signal.secondaryLabel))

        textView.attributedText = attributedTitle
        textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]
        return textView
    }

    private func backupDetailsSection() -> OWSTableSection? {
        switch lastBackupState {
        case .unavailable:
            return nil
        case .loading, .loaded:
            break
        }

        let section = OWSTableSection()
        section.headerTitle = BackupSettingsView.Strings.backupDetailsSectionHeader
        section.add(OWSTableItem(customCellBlock: { [unowned self] in
            self.lastBackupCell()
        }))
        return section
    }

    private func lastBackupCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none

        let titleLabel = UILabel()
        titleLabel.text = BackupSettingsView.Strings.lastBackupLabel
        titleLabel.font = .dynamicTypeBody
        titleLabel.textColor = UIColor.Signal.label

        let trailingView: UIView
        switch lastBackupState {
        case .loading:
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            trailingView = spinner
        case .loaded(let date):
            let valueLabel = UILabel()
            valueLabel.text = BackupSettingsView.Strings.lastBackupString(date: date)
            valueLabel.font = .dynamicTypeBody
            valueLabel.textColor = UIColor.Signal.secondaryLabel
            trailingView = valueLabel
        case .unavailable:
            trailingView = UIView()
        }
        trailingView.setContentHuggingHorizontalHigh()
        trailingView.setCompressionResistanceHorizontalHigh()

        let hStack = UIStackView(arrangedSubviews: [titleLabel, UIView(), trailingView])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 8

        cell.contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()

        return cell
    }

    // MARK: - CDN fetch

    private func fetchLastBackupDate() {
        lastBackupFetchTask = Task {
            let date = await self.loadLastBackupDate()
            self.lastBackupState = date.map { .loaded($0) } ?? .unavailable
            self.updateTableContents()
        }
    }

    private static func loadLastBackupDateFromCDN() async -> Date? {
        let accountKeyStore = DependenciesBridge.shared.accountKeyStore
        let backupArchiveManager = DependenciesBridge.shared.backupArchiveManager
        let backupRequestManager = DependenciesBridge.shared.backupRequestManager
        let db = DependenciesBridge.shared.db
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        do {
            let registeredState = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
            let backupKey = db.read { tx in
                return accountKeyStore.getMessageRootBackupKey(aci: registeredState.localIdentifiers.aci, tx: tx)
            }
            guard let backupKey else {
                return nil
            }
            let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: backupKey,
                localAci: registeredState.localIdentifiers.aci,
                auth: .implicit(),
                logger: logger,
            )
            let cdnInfo = try await backupArchiveManager.backupCdnInfo(
                backupKey: backupKey,
                backupAuth: backupAuth,
                logger: logger,
            )
            return cdnInfo.fileInfo.lastModified
        } catch {
            logger.warn("Failed to fetch last backup date on linked device: \(error)")
            return nil
        }
    }

    // MARK: - Subscription fetch

    private func fetchSubscription() {
        subscriptionFetchTask = Task {
            let state = await self.loadSubscription()
            self.subscriptionState = state
            self.updateTableContents()
        }
    }

    private static func loadSubscriptionFromServer() async -> SubscriptionState {
        let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
        let db = DependenciesBridge.shared.db
        let networkManager = SSKEnvironment.shared.networkManagerRef

        // This is only called on `.paid`, so not subscriber ID means tester
        guard let subscriberID = db.read(block: { backupSubscriptionManager.getIAPSubscriberData(tx: $0)?.subscriberId }) else {
            return .paidButFreeForTesters
        }

        do {
            guard
                let subscription = try await SubscriptionFetcher(networkManager: networkManager).fetch(subscriberID: subscriberID),
                subscription.active
            else {
                return .notFound
            }
            return .loaded(PaidSubscription(
                price: subscription.amount,
                endOfCurrentPeriod: subscription.endOfCurrentPeriod,
                isCanceled: subscription.cancelAtEndOfPeriod,
            ))
        } catch {
            logger.warn("Failed to fetch backup subscription on linked device: \(error)")
            return .unavailable
        }
    }

    private func buildOtherWaysHeaderView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_OTHER_WAYS_HEADER",
            comment: "Section header on the Backups settings landing page.",
        )
        label.font = .dynamicTypeHeadlineClamped
        label.textColor = .Signal.label
        label.numberOfLines = 0

        let container = UIView()
        container.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: Self.cellHInnerMargin)
        label.autoPinEdge(toSuperviewEdge: .trailing, withInset: Self.cellHInnerMargin)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: (defaultSpacingBetweenSections ?? 0) + 12)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 10)
        return container
    }

    private func buildOnDeviceBackupsItem() -> OWSTableItem {
        let (shouldSkipLocalBackupsOnboarding, localBackupsEnabled) = db.read { tx in
            let localBackupsEnabled = localFileBackupsStore.localBackupsEnabled(tx: tx)
            let skipOnboarding: Bool = {
                if localFileBackupsStore.shouldOverrideShowLocalBackupsOnboarding(tx: tx) {
                    return false
                }
                return localBackupsEnabled
            }()
            return (skipOnboarding, localBackupsEnabled)
        }

        return OWSTableItem(
            customCellBlock: {
                OWSTableItem.buildImageCell(
                    image: UIImage(named: "device-phone")?.withRenderingMode(.alwaysTemplate),
                    tintColor: UIColor.Signal.label,
                    itemName: OWSLocalizedString(
                        "BACKUP_SETTINGS_LANDING_ON_DEVICE_BACKUPS",
                        comment: "Label for the On-Device Backups option on the Backups settings landing page.",
                    ),
                    accessoryText: localBackupsEnabled ? CommonStrings.switchOn : nil,
                    accessoryType: .disclosureIndicator,
                )
            },
            actionBlock: { [weak self] in
                guard let navigationController = self?.navigationController else { return }
                navigationController.pushViewController(
                    BackupOnboardingCoordinator(
                        backupType: .local,
                    ).prepareForPresentation(
                        inNavController: navigationController,
                        shouldSkipOnboarding: shouldSkipLocalBackupsOnboarding,
                    ),
                    animated: true,
                )
            },
        )
    }

    // MARK: - Previews

#if DEBUG
    fileprivate init(
        displayTier: DisplayTier,
        loadLastBackupDate: @escaping () async -> Date?,
        loadSubscription: @escaping () async -> SubscriptionState = { .unavailable },
    ) {
        self.currentDisplayTier = { displayTier }
        self.loadLastBackupDate = loadLastBackupDate
        self.loadSubscription = loadSubscription
        self.localFileBackupsStore = LocalFileBackupStore()
        self.db = DependenciesBridge.shared.db

        super.init()
    }
#endif
}

#if DEBUG
@available(iOS 17, *)
#Preview("Paid") {
    NavigationPreviewController(
        viewController: LinkedDeviceBackupSettingsViewController(
            displayTier: .paid,
            loadLastBackupDate: {
                try? await Task.sleep(for: .seconds(1))
                return Date().addingTimeInterval(-2 * .hour)
            },
            loadSubscription: {
                .loaded(LinkedDeviceBackupSettingsViewController.PaidSubscription(
                    price: FiatMoney(currencyCode: "USD", value: 2.99),
                    endOfCurrentPeriod: Date().addingTimeInterval(30 * .day),
                    isCanceled: false,
                ))
            },
        ),
    )
}

@available(iOS 17, *)
#Preview("Canceled") {
    NavigationPreviewController(
        viewController: LinkedDeviceBackupSettingsViewController(
            displayTier: .paid,
            loadLastBackupDate: { Date().addingTimeInterval(-2 * .hour) },
            loadSubscription: {
                .loaded(LinkedDeviceBackupSettingsViewController.PaidSubscription(
                    price: FiatMoney(currencyCode: "USD", value: 2.99),
                    endOfCurrentPeriod: Date().addingTimeInterval(30 * .day),
                    isCanceled: true,
                ))
            },
        ),
    )
}

@available(iOS 17, *)
#Preview("Subscription Not Found") {
    NavigationPreviewController(
        viewController: LinkedDeviceBackupSettingsViewController(
            displayTier: .paid,
            loadLastBackupDate: { Date().addingTimeInterval(-2 * .hour) },
            loadSubscription: { .notFound },
        ),
    )
}

@available(iOS 17, *)
#Preview("Paid (Free for Testers)") {
    NavigationPreviewController(
        viewController: LinkedDeviceBackupSettingsViewController(
            displayTier: .paid,
            loadLastBackupDate: { Date().addingTimeInterval(-2 * .hour) },
            loadSubscription: { .paidButFreeForTesters },
        ),
    )
}

@available(iOS 17, *)
#Preview("Free") {
    NavigationPreviewController(
        viewController: LinkedDeviceBackupSettingsViewController(
            displayTier: .free(mediaDays: 45),
            loadLastBackupDate: {
                try? await Task.sleep(for: .seconds(1))
                return Date().addingTimeInterval(-3 * .day)
            },
        ),
    )
}

@available(iOS 17, *)
#Preview("None") {
    NavigationPreviewController(
        viewController: LinkedDeviceBackupSettingsViewController(
            displayTier: .disabled,
            loadLastBackupDate: { nil },
        ),
    )
}
#endif
