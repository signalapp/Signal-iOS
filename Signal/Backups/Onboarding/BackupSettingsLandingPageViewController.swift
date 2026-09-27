//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class BackupSettingsLandingPageViewController: OWSTableViewController2 {
    private let backupPlanManager: BackupPlanManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionIssueStore: BackupSubscriptionIssueStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let localFileBackupsStore: LocalFileBackupStore
    private let db: DB

    private var subscriptionLoadingState: BackupSubscriptionLoadingState = .loading

    override convenience init() {
        self.init(
            backupPlanManager: DependenciesBridge.shared.backupPlanManager,
            backupSettingsStore: BackupSettingsStore(),
            backupSubscriptionIssueStore: BackupSubscriptionIssueStore(),
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            localFileBackupsStore: LocalFileBackupStore(),
            db: DependenciesBridge.shared.db,
        )
    }

    init(
        backupPlanManager: BackupPlanManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionIssueStore: BackupSubscriptionIssueStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        localFileBackupsStore: LocalFileBackupStore,
        db: DB,
    ) {
        self.backupPlanManager = backupPlanManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionIssueStore = backupSubscriptionIssueStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.localFileBackupsStore = localFileBackupsStore
        self.db = db
    }

    // MARK: -

    private let loadBackupSubscriptionTaskQueue = SerialTaskQueue()

    fileprivate func loadBackupSubscription() {
        loadBackupSubscriptionTaskQueue.enqueueCancellingPrevious { @MainActor [self] in
            if Task.isCancelled {
                return
            }

            switch subscriptionLoadingState {
            case .loading, .loaded:
                break
            case .networkError, .notRegisteredError, .genericError:
                subscriptionLoadingState = .loading
            }

            let newLoadingState: BackupSubscriptionLoadingState
            do {
                let backupSubscription = try await _loadBackupSubscription()
                newLoadingState = .loaded(backupSubscription)
            } catch is CancellationError {
                // We were cancelled: leave it loading. Whoever cancelled us
                // should be trying again.
                return
            } catch let error where error.isNetworkFailureOrTimeout {
                newLoadingState = .networkError
            } catch is NotRegisteredError {
                newLoadingState = .notRegisteredError
            } catch {
                newLoadingState = .genericError
            }

            subscriptionLoadingState = newLoadingState
            self.updateContents()
        }
    }

    private func _loadBackupSubscription() async throws -> BackupSubscriptionLoadingState.LoadedBackupSubscription {
        return try await BackupSubscriptionLoader(
            backupPlanManager: backupPlanManager,
            backupSubscriptionManager: backupSubscriptionManager,
            backupSubscriptionIssueStore: backupSubscriptionIssueStore,
            db: db,
        ).load()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_BACKUPS",
            comment: "Label for the 'backups' section of app settings.",
        )
        updateContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateContents()
        loadBackupSubscription()
    }

    private func updateContents() {
        let contents = OWSTableContents()

        let titleSection = OWSTableSection()
        titleSection.footerTitle = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_PAGE_SUBTITLE",
            comment: "Subtitle on the Backups settings landing page.",
        )
        contents.add(titleSection)

        contents.add(OWSTableSection(items: [buildSignalBackupsCardItem()]))

        let onDeviceSection = OWSTableSection()
        onDeviceSection.headerTitle = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_OTHER_WAYS_HEADER",
            comment: "Section header on the Backups settings landing page.",
        )
        onDeviceSection.footerTitle = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_ON_DEVICE_BACKUPS_FOOTER",
            comment: "Footer text below the On-Device Backups row on the Backups settings landing page.",
        )
        onDeviceSection.add(buildOnDeviceBackupsItem())
        contents.add(onDeviceSection)

        self.contents = contents
    }

    // MARK: - Table items

    private func buildSignalBackupsCardItem() -> OWSTableItem {
        let (shouldSkipBackupsOnboarding, lastBackupDetails) = db.read { tx in
            let lastBackupDetails = backupSettingsStore.lastBackupDetails(tx: tx)

            if backupSettingsStore.shouldOverrideShowBackupsOnboarding(tx: tx) {
                return (false, lastBackupDetails)
            }

            return (backupSettingsStore.haveBackupsEverBeenEnabled(tx: tx), lastBackupDetails)
        }

        return OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self else { return OWSTableItem.newCell() }
                return self.buildSignalBackupsCardCell(
                    shouldSkipBackupsOnboarding: shouldSkipBackupsOnboarding,
                    lastBackupDetails: lastBackupDetails,
                )
            },
            actionBlock: { [weak self] in
                self?.showRemoteBackups(shouldSkipOnboarding: shouldSkipBackupsOnboarding)
            },
        )
    }

    private func _bodyText(
        for backupSubscription: BackupSubscriptionLoadingState.LoadedBackupSubscription,
        lastBackupDetails: BackupSettingsStore.LastBackupDetails?,
    ) -> String {
        switch backupSubscription {
        case .paid(let price, let renewalDate):
            let priceText = BackupSettingsView.Strings.paidPlanPriceText(price)
            let renewalDateText = BackupSettingsView.Strings.paidPlanRenewalText(renewalDate)
            if let lastBackupDetails {
                let lastBackupDateString = BackupSettingsView.Strings.prefixedLastBackupString(date: lastBackupDetails.date)
                return [priceText, renewalDateText, lastBackupDateString].joined(separator: "\n")
            } else {
                return [priceText, renewalDateText].joined(separator: "\n")
            }
        case .freeAndEnabled, .paidButFreeForTesters:
            let freePlanDescription = BackupSettingsView.Strings.freePlanDescription
            if let lastBackupDetails {
                let lastBackupDateString = BackupSettingsView.Strings.prefixedLastBackupString(date: lastBackupDetails.date)
                return [freePlanDescription, lastBackupDateString].joined(separator: "\n")
            } else {
                return freePlanDescription
            }
        case .paidButExpiring(let expirationDate):
            let canceledText = BackupSettingsView.Strings.paidPlanCanceledText
            let expiredText = BackupSettingsView.Strings.paidPlanExpirationText(expirationDate)
            return [canceledText, expiredText].joined(separator: "\n")
        case
            .freeAndDisabled,
            .paidButExpired,
            .paidButFailedToRenew,
            .paidButIAPNotFoundLocally:
            return OWSLocalizedString(
                "BACKUP_SETTINGS_LANDING_SIGNAL_BACKUPS_BODY",
                comment: "Description of Signal Secure Backups on the Backups settings landing page.",
            )
        }
    }

    private func buildSignalBackupsCardCell(
        shouldSkipBackupsOnboarding: Bool,
        lastBackupDetails: BackupSettingsStore.LastBackupDetails?,
    ) -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let titleText = OWSLocalizedString(
            "BACKUP_SETTINGS_LANDING_SIGNAL_BACKUPS_TITLE",
            comment: "Title for the Signal Secure Backups cell on the Backups settings landing page.",
        )

        let bodyText: String
        switch subscriptionLoadingState {
        case .loaded(let loadedBackupSubscription):
            bodyText = _bodyText(for: loadedBackupSubscription, lastBackupDetails: lastBackupDetails)
        case .loading, .networkError, .notRegisteredError, .genericError:
            // Show generic backups text if we can't load the subscription state.
            bodyText = OWSLocalizedString(
                "BACKUP_SETTINGS_LANDING_SIGNAL_BACKUPS_BODY",
                comment: "Description of Signal Secure Backups on the Backups settings landing page.",
            )
        }

        let actionText: String = if shouldSkipBackupsOnboarding {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LANDING_VIEW_SETTINGS_BUTTON",
                comment: "Button to view settings for remote backups on the Backups settings landing page.",
            )
        } else {
            OWSLocalizedString(
                "BACKUP_SETTINGS_LANDING_SET_UP_BUTTON",
                comment: "Button to begin setting up Signal Secure Backups on the Backups settings landing page.",
            )
        }

        let titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.font = .dynamicTypeHeadlineClamped
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = bodyText
        bodyLabel.font = .dynamicTypeSubheadlineClamped
        bodyLabel.textColor = .Signal.secondaryLabel
        bodyLabel.numberOfLines = 0

        var buttonConfig = UIButton.Configuration.gray()
        buttonConfig.title = actionText
        buttonConfig.cornerStyle = .capsule
        buttonConfig.baseBackgroundColor = .Signal.tertiaryFill
        buttonConfig.baseForegroundColor = .Signal.label
        buttonConfig.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.medium())
        buttonConfig.contentInsets = .init(top: 6, leading: 16, bottom: 6, trailing: 16)

        let remoteBackupsButton = UIButton(configuration: buttonConfig)
        remoteBackupsButton.isUserInteractionEnabled = false // Button is decorative. Tapping anywhere on row performs the action.
        remoteBackupsButton.isAccessibilityElement = false
        remoteBackupsButton.setContentHuggingHorizontalHigh()

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, remoteBackupsButton])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8
        textStack.setCustomSpacing(15, after: bodyLabel)

        let logoImageView = UIImageView(image: UIImage(named: "backups-logo"))
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.autoSetDimensions(to: CGSize(square: 56))
        logoImageView.setContentHuggingHorizontalHigh()
        logoImageView.setCompressionResistanceHorizontalHigh()
        logoImageView.isAccessibilityElement = false

        let contentStack = UIStackView(arrangedSubviews: [textStack, logoImageView])
        contentStack.axis = .horizontal
        contentStack.alignment = .top
        contentStack.spacing = 12

        cell.contentView.addSubview(contentStack)
        contentStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 20, vMargin: 20))

        cell.isAccessibilityElement = true
        cell.accessibilityTraits = .button
        cell.accessibilityLabel = "\(titleText), \(bodyText), \(actionText)"

        return cell
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

    // MARK: - Actions

    private func showRemoteBackups(shouldSkipOnboarding: Bool) {
        guard let navigationController else { return }

        navigationController.pushViewController(
            BackupOnboardingCoordinator(
                backupType: .remote,
            ).prepareForPresentation(
                inNavController: navigationController,
                shouldSkipOnboarding: shouldSkipOnboarding,
            ),
            animated: true,
        )
    }
}
