//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

class AccountSettingsViewController: OWSTableViewController2 {

    private enum MfaLoadState {
        case loading
        case loaded([ConfirmedMfaKey])
        case failed
    }

    private var mfaState: MfaLoadState = .loading
    private var loadTask: Task<Void, Never>?
    private let context: ViewControllerContext

    private var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }
    private var serviceProvider: any ServiceProvider { DependenciesBridge.shared.chatConnectionManager }
    private let dateProvider = { Date() }

    private static let twoFactorDateAddedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMddyyyy")
        return formatter
    }()

    override init() {
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        super.init()
    }

    private let accountSettingsTitle = OWSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings.")
    private let proceedTitle = OWSLocalizedString("PROCEED_BUTTON", comment: "")

    override func viewDidLoad() {
        super.viewDidLoad()

        title = self.accountSettingsTitle

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        tableView.layoutIfNeeded()

        let tsRegistrationState = tsAccountManager.registrationStateWithMaybeSneakyTransaction
        if
            let registeredState = try? tsRegistrationState.registeredState(),
            registeredState.isPrimary,
            !registeredState.localIdentifiers.hasPhoneNumber
        {
            loadMfaState()
        }
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let tsRegistrationState = tsAccountManager.registrationStateWithMaybeSneakyTransaction
        if
            let registeredState = try? tsRegistrationState.registeredState(),
            registeredState.isPrimary,
            !registeredState.localIdentifiers.hasPhoneNumber
        {
            contents.add(signalLoginSection(registeredState: registeredState))
            contents.add(twoFactorAuthSection())
        }

        // Show the change pin and reglock sections
        if
            let registeredState = try? tsRegistrationState.registeredState(),
            registeredState.isPrimary,
            registeredState.localIdentifiers.hasPhoneNumber
        {
            let pinSection = OWSTableSection()
            let isPinEnabled = SSKEnvironment.shared.ows2FAManagerRef.isPinEnabledWithSneakyTransaction

            pinSection.headerTitle = OWSLocalizedString(
                "SETTINGS_PINS_TITLE",
                comment: "Title for the 'PINs' section of the privacy settings.",
            )
            pinSection.footerAttributedTitle = NSAttributedString.composed(of: [
                OWSLocalizedString(
                    "SETTINGS_PINS_FOOTER",
                    comment: "Footer for the 'PINs' section of the privacy settings.",
                ),
                " ",
                CommonStrings.learnMore.styled(with: .link(URL.Support.pin)),
            ])
            .styled(with: Self.defaultFooterTextStyle)

            pinSection.add(.disclosureItem(
                withText: isPinEnabled
                    ? OWSLocalizedString(
                        "SETTINGS_PINS_ITEM",
                        comment: "Label for the 'pins' item of the privacy settings when the user does have a pin.",
                    )
                    : OWSLocalizedString(
                        "SETTINGS_PINS_ITEM_CREATE",
                        comment: "Label for the 'pins' item of the privacy settings when the user doesn't have a pin.",
                    ),
                actionBlock: { [weak self] in
                    if isPinEnabled {
                        self?.showChangePin()
                    } else {
                        self?.showCreatePin()
                    }
                },
            ))

            // Reminders toggle.
            if isPinEnabled {
                pinSection.add(.switch(
                    withText: OWSLocalizedString(
                        "SETTINGS_PIN_REMINDER_SWITCH_LABEL",
                        comment: "Label for the 'pin reminder' switch of the privacy settings.",
                    ),
                    isOn: { SSKEnvironment.shared.ows2FAManagerRef.areRemindersEnabled },
                    actionBlock: { [weak self] uiSwitch in
                        self?.didTogglePINRemindersEnabled(uiSwitch)
                    },
                ))
            }

            contents.add(pinSection)

            let regLockSection = OWSTableSection()
            regLockSection.footerTitle = OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_PINS_AUTH_FOOTER",
                comment: "Footer for the 'two factor auth' section of the privacy settings when Signal PINs are available.",
            )

            regLockSection.add(.switch(
                withText: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_AUTH_SWITCH_LABEL",
                    comment: "Label for the 'enable registration lock' switch of the privacy settings.",
                ),
                isOn: { SSKEnvironment.shared.ows2FAManagerRef.isRegistrationLockV2Enabled },
                actionBlock: { [weak self] uiSwitch in
                    self?.didToggleRegistrationLockV2Enabled(uiSwitch)
                },
            ))

            contents.add(regLockSection)

            let advancedSection = OWSTableSection()
            advancedSection.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "SETTINGS_ADVANCED_PIN_SETTINGS",
                    comment: "Label for the 'advanced pin settings' button.",
                ),
                actionBlock: { [weak self] in
                    let vc = AdvancedPinSettingsTableViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                },
            ))
            contents.add(advancedSection)
        }

        if let deregisteredState = tsRegistrationState.deregisteredState {
            let accountSection = OWSTableSection()
            accountSection.headerTitle = accountSettingsTitle
            accountSection.add(.actionItem(
                withText: { () -> String in
                    if deregisteredState.isPrimary {
                        return OWSLocalizedString("SETTINGS_REREGISTER_BUTTON", comment: "Label for re-registration button.")
                    } else {
                        return OWSLocalizedString("SETTINGS_RELINK_BUTTON", comment: "Label for re-link button.")
                    }
                }(),
                textColor: .Signal.accent,
                actionBlock: {
                    if deregisteredState.isPrimary {
                        RegistrationUtils.showReRegistration(deregisteredState: deregisteredState)
                    } else {
                        RegistrationUtils.showReLinking(deregisteredState: deregisteredState)
                    }
                },
            ))
            accountSection.add(.actionItem(
                withText: OWSLocalizedString(
                    "SETTINGS_DELETE_DATA_BUTTON",
                    comment: "Label for 'delete data' button.",
                ),
                textColor: .Signal.red,
                actionBlock: { [weak self] in
                    self?.deleteUnregisteredUserData()
                },
            ))
            contents.add(accountSection)
        } else if let registeredState = try? tsRegistrationState.registeredState() {
            if registeredState.isPrimary {
                let accountSection = OWSTableSection()
                accountSection.headerTitle = accountSettingsTitle
                switch self.changeNumberState() {
                case .disallowed:
                    break
                case .allowed:
                    accountSection.add(.actionItem(
                        withText: OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_BUTTON", comment: "Label for button in settings views to change phone number"),
                        accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "change_phone_number"),
                        actionBlock: { [weak self] in
                            guard let self else {
                                return
                            }
                            // Fetch the state again in case it changed from under us
                            // between when the button was rendered and when it was tapped.
                            switch self.changeNumberState() {
                            case .disallowed:
                                return
                            case .allowed(let changeNumberParams):
                                self.changePhoneNumber(changeNumberParams)
                            }
                        },
                    ))
                }
                accountSection.add(.actionItem(
                    withText: OWSLocalizedString(
                        "SETTINGS_ACCOUNT_DATA_REPORT_BUTTON",
                        comment: "Label for button in settings to get your account data report",
                    ),
                    accessibilityIdentifier: UIView.accessibilityIdentifier(
                        in: self,
                        name: "request_account_data_report",
                    ),
                    actionBlock: { [weak self] in
                        self?.requestAccountDataReport()
                    },
                ))
                accountSection.add(.item(
                    name: OWSLocalizedString("SETTINGS_DELETE_ACCOUNT_BUTTON", comment: ""),
                    textColor: .Signal.red,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_account"),
                    actionBlock: { [weak self] in
                        self?.unregisterUser(registeredState: registeredState)
                    },
                ))
                contents.add(accountSection)
            } else {
                let cardSection = OWSTableSection()
                cardSection.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }
                    return self.linkedDeviceCardCell()
                }))
                contents.add(cardSection)

                let deleteSection = OWSTableSection()
                deleteSection.add(.actionItem(
                    withText: OWSLocalizedString(
                        "SETTINGS_LINKED_DEVICE_DELETE_DATA_BUTTON",
                        comment: "Label for a button that deletes all Signal data from a linked device.",
                    ),
                    textColor: .Signal.red,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_data"),
                    actionBlock: { [weak self] in
                        self?.unlinkDevice()
                    },
                ))
                deleteSection.footerTitle = OWSLocalizedString(
                    "SETTINGS_LINKED_DEVICE_DELETE_DATA_FOOTER",
                    comment: "Footer below the 'delete app data' button, shown on a linked device's account settings.",
                )
                contents.add(deleteSection)
            }
        } else {
            owsFailDebug("can't view account settings for state: \(tsRegistrationState)")
        }

        self.contents = contents
    }

    // MARK: - Section contents

    private func signalLoginSection(registeredState: RegisteredState) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = OWSLocalizedString(
            "SETTINGS_SIGNAL_LOGIN_TITLE",
            comment: "Title for the 'Signal Login' section of the account settings.",
        )
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SETTINGS_SIGNAL_LOGIN_FOOTER",
                comment: "Footer for the 'Signal Login' section of the account settings.",
            ),
            " ",
            // TODO[#less]: Link to a Signal Login support article once there is one.
            CommonStrings.learnMore.styled(with: .link(URL.Support.generic)),
        ])
        .styled(with: Self.defaultFooterTextStyle)

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            return self.signalLoginCardCell()
        }, actionBlock: { [weak self] in
            guard let self else { return }
            Task {
                guard await LocalDeviceAuthentication(useCase: .viewRecoveryKey).performBiometricAuth() != nil else { return }
                let state = RegistrationSignalLoginDetailsState(
                    aci: registeredState.localIdentifiers.aci,
                    aep: self.getAccountEntropyPool(),
                    hideBackButton: false,
                    confirmLogin: {},
                )
                let vc = RegistrationSignalLoginDetailsViewController(
                    state: state,
                    goToNextStep: {
                        let viewController = RegistrationSignalLoginFullDetailsViewController(
                            state: RegistrationSignalLoginFullDetailsState(
                                aci: state.aci,
                                aep: state.aep,
                            ),
                        )
                        self.present(UINavigationController(rootViewController: viewController), animated: true)
                    },
                )
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }))
        return section
    }

    private func signalLoginCardCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.accessoryType = .disclosureIndicator

        let cardImage = UIImage.signalLoginCardSmall
        let cardImageView = UIImageView(image: cardImage)
        cardImageView.contentMode = .scaleAspectFit
        cardImageView.translatesAutoresizingMaskIntoConstraints = false
        let cardHeight: CGFloat = 40
        NSLayoutConstraint.activate([
            cardImageView.heightAnchor.constraint(equalToConstant: cardHeight),
            cardImageView.widthAnchor.constraint(
                equalToConstant: cardHeight * cardImage.size.width / max(cardImage.size.height, 1),
            ),
        ])

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "SETTINGS_SIGNAL_LOGIN_ACCOUNT_AND_RECOVERY",
            comment: "Label for the row in the 'Signal Login' section of the account settings.",
        )
        titleLabel.font = OWSTableItem.primaryLabelFont
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0

        let hStack = UIStackView(arrangedSubviews: [cardImageView, titleLabel])
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 12
        cell.contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()

        return cell
    }

    private func twoFactorAuthSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = OWSLocalizedString(
            "SETTINGS_TWO_FACTOR_METHODS_TITLE",
            comment: "Title for the 'Two-Factor Authentication' section of the account settings.",
        )
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_METHODS_FOOTER",
                comment: "Footer for the 'Two-Factor Authentication' section of the account settings.",
            ),
            " ",
            // TODO[#less]: Link to a two-factor authentication support article once there is one.
            CommonStrings.learnMore.styled(with: .link(URL.Support.generic)),
        ])
        .styled(with: Self.defaultFooterTextStyle)

        section.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            return self.twoFactorSetUpCell()
        }))

        switch mfaState {
        case .loading, .failed: // TODO[#less]: Add error screen for failed load
            break
        case .loaded(let methods):
            for method in methods {
                section.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }
                    guard let cell = self.twoFactorMethodCell(method) else {
                        Logger.error("Unable to build MFA cell")
                        return UITableViewCell()
                    }
                    return cell
                }))
            }
        }

        return section
    }

    private func loadMfaState() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let newState: MfaLoadState
            do {
                let methods = try await self.serviceProvider.withAuthService(.accounts) {
                    try await $0.listMfaKeys(svrKey: self.getAccountEntropyPool().getMasterKey().asSvrKey)
                }
                newState = .loaded(methods)
            } catch {
                newState = .failed
            }
            if !Task.isCancelled {
                self.mfaState = newState
                self.updateTableContents()
            }
        }
    }

    private func twoFactorSetUpCell() -> UITableViewCell {
        let title = OWSLocalizedString(
            "SETTINGS_TWO_FACTOR_METHODS_SET_UP",
            comment: "Row Label for the 'Two-Factor Authentication' section that adds a new two-factor authentication method.",
        )
        let cell = OWSTableItem.buildImageCell(
            image: .plus,
            tintColor: .Signal.label,
            itemName: title,
        )
        cell.selectionStyle = .none

        // The whole row opens the menu of methods to set up.
        let menuButton = UIButton(type: .custom)
        menuButton.menu = UIMenu(children: [
            UIAction(
                title: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_AUTHENTICATOR_APP",
                    comment: "Menu option to set up an authenticator app for two-factor authentication.",
                ),
                subtitle: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_AUTHENTICATOR_APP_SUBTITLE",
                    comment: "Subtitle for the menu option to set up an authenticator app for two-factor authentication.",
                ),
                image: .devicePhone,
            ) { [weak self] _ in
                Task {
                    do {
                        try await self?.didSelectSetUpAuthenticatorApp()
                    } catch {
                        // TODO[#less]: Surface this error to the user
                        Logger.error("Error setting up authenticator app: \(error)")
                    }
                }
            },
            UIAction(
                title: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_WEBAUTHN",
                    comment: "Menu option to set up webauthn for two-factor authentication.",
                ),
                subtitle: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_WEBAUTHN_SUBTITLE",
                    comment: "Subtitle for the menu option to set up webauthn for two-factor authentication.",
                ),
                image: .key,
            ) { [weak self] _ in
                self?.didSelectSetUpWebAuthn()
            },
        ])
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = title
        cell.contentView.addSubview(menuButton)
        menuButton.autoPinEdgesToSuperviewEdges()

        return cell
    }

    private func twoFactorMethodCell(_ method: ConfirmedMfaKey) -> UITableViewCell? {
        let icon: UIImage
        let kindLabel: String
        switch method.kind {
        case .totp:
            icon = .devicePhone
            kindLabel = OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_METHODS_KIND_AUTHENTICATOR_APP",
                comment: "Describes a two-factor authentication method that is an authenticator app.",
            )
        case .webAuthn:
            icon = .key
            kindLabel = OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_METHODS_KIND_WEBAUTHN",
                comment: "Describes a webauthn two-factor authentication method.",
            )
        case .unknown:
            return nil
        }
        var addedLabel: String?
        if let createDate = method.metadata?.createdAt {
            addedLabel = String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_ADDED_FORMAT",
                    comment: "Shows when a two-factor authentication method was added. Embeds {{date}}.",
                ),
                Self.twoFactorDateAddedFormatter.string(from: createDate),
            )
        }
        let subtitle = addedLabel.map {
            String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "JOINED_WITH_DOT",
                    comment: "Two strings, joined by a dot. Embeds {first} and {second}, which are on opposite sides of the dot",
                ),
                arguments: [kindLabel, $0],
            )
        } ?? kindLabel

        let moreButton = UIButton(type: .system)
        moreButton.setImage(.more, for: .normal)
        moreButton.tintColor = .Signal.label
        moreButton.accessibilityLabel = OWSLocalizedString(
            "SETTINGS_TWO_FACTOR_METHODS_MORE_OPTIONS",
            comment: "Accessibility label for the button for renaming a two-factor authentication method.",
        )
        moreButton.menu = UIMenu(children: [
            UIAction(
                title: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_RENAME",
                    comment: "Menu option to rename a two-factor authentication method.",
                ),
                image: .edit,
            ) { [weak self] _ in
                guard let self else { return }
                self.showRenameTwoFactorMethod(accountEntropyPool: self.getAccountEntropyPool(), method: method)
            },
            UIAction(
                title: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_REMOVE",
                    comment: "Menu option to remove a two-factor authentication method.",
                ),
                image: .minusCircle,
                attributes: .destructive,
            ) { [weak self] _ in
                self?.showRemoveTwoFactorMethod(method)
            },
        ])
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.setContentHuggingHigh()
        moreButton.setCompressionResistanceHigh()

        let cell = OWSTableItem.buildImageCell(
            image: icon,
            tintColor: .Signal.label,
            itemName: method.metadata?.name ?? CommonStrings.unknownValue,
            subtitle: subtitle,
            accessoryContentView: moreButton,
        )
        cell.selectionStyle = .none
        return cell
    }

    private func linkedDeviceCardCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none

        let iconImageView = UIImageView(image: .devices)
        iconImageView.tintColor = .Signal.label
        iconImageView.setContentHuggingHigh()
        iconImageView.setCompressionResistanceHigh()

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "SETTINGS_LINKED_DEVICE_ACCOUNT_CARD_TITLE",
            comment: "Title of a card on a linked device's account settings, indicating that this is a linked device.",
        )
        titleLabel.font = .dynamicTypeBody
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "SETTINGS_LINKED_DEVICE_ACCOUNT_CARD_SUBTITLE",
            comment: "Subtitle of a card on a linked device's account settings, explaining that account settings are managed on the primary device.",
        )
        subtitleLabel.font = .dynamicTypeSubheadline
        subtitleLabel.textColor = .Signal.secondaryLabel
        subtitleLabel.numberOfLines = 0

        let learnMoreButton = UIButton(
            configuration: .smallSecondary(title: CommonStrings.learnMore),
            primaryAction: UIAction { [weak self] _ in
                self?.present(LinkedDeviceInfoSheet(), animated: true)
            },
        )

        let buttonRow = UIStackView(arrangedSubviews: [learnMoreButton, .hStretchingSpacer()])
        buttonRow.axis = .horizontal

        let vStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, buttonRow])
        vStack.axis = .vertical
        vStack.spacing = 4
        vStack.setCustomSpacing(20, after: subtitleLabel)

        let hStack = UIStackView(arrangedSubviews: [iconImageView, vStack])
        hStack.axis = .horizontal
        hStack.spacing = 12
        hStack.alignment = .top
        cell.contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()

        return cell
    }

    // MARK: - Account

    private func unlinkDevice() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("CONFIRM_DELETE_LINKED_DATA_TITLE", comment: ""),
            message: OWSLocalizedString("CONFIRM_DELETE_LINKED_DATA_TEXT", comment: ""),
            proceedTitle: proceedTitle,
            proceedStyle: .destructive,
            proceedAction: { _ in
                let localDeviceId = DependenciesBridge.shared.tsAccountManager.storedDeviceIdWithMaybeTransaction
                let keyFetcher = SSKEnvironment.shared.databaseStorageRef.keyFetcher
                let registrationStateChangeManager = DependenciesBridge.shared.registrationStateChangeManager

                ModalActivityIndicatorViewController.present(
                    fromViewController: self,
                    title: CommonStrings.deletingModal,
                ) { _ in
                    await SignalApp.shared.resetLinkedAppDataAndExit(
                        localDeviceId: localDeviceId,
                        keyFetcher: keyFetcher,
                        registrationStateChangeManager: registrationStateChangeManager,
                    )
                }
            },
            fromViewController: self,
        )
    }

    private func unregisterUser(registeredState: RegisteredState) {
        let vc = DeleteAccountConfirmationViewController(registeredState: registeredState)
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    private func deleteUnregisteredUserData() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("CONFIRM_DELETE_DATA_TITLE", comment: ""),
            message: OWSLocalizedString("CONFIRM_DELETE_DATA_TEXT", comment: ""),
            proceedTitle: proceedTitle,
            proceedStyle: .destructive,
            proceedAction: { _ in
                ModalActivityIndicatorViewController.present(
                    fromViewController: self,
                    title: CommonStrings.deletingModal,
                ) { _ in
                    let keyFetcher = SSKEnvironment.shared.databaseStorageRef.keyFetcher
                    SignalApp.shared.resetAppDataAndExit(keyFetcher: keyFetcher)
                }
            },
            fromViewController: self,
        )
    }

    private func requestAccountDataReport() {
        let vc = RequestAccountDataReportViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private enum ChangeNumberState {
        case disallowed
        case allowed(RegistrationMode.ChangeNumberParams)
    }

    private func changeNumberState() -> ChangeNumberState {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return databaseStorage.read { transaction -> ChangeNumberState in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let registeredState = try? tsAccountManager.registeredState(tx: transaction)
            guard let registeredState else {
                return .disallowed
            }
            let loader = RegistrationCoordinatorLoaderImpl(dependencies: .from(self))
            switch loader.restoreLastMode(transaction: transaction) {
            case .none, .changingNumber:
                break
            case .registering, .reRegistering:
                // Don't allow changing number if we are in the middle of registering.
                return .disallowed
            }
            guard
                let localE164 = E164(registeredState.localIdentifiers.phoneNumber),
                let authToken = tsAccountManager.storedServerAuthToken(tx: transaction),
                let localDeviceId = tsAccountManager.storedDeviceId(tx: transaction).ifValid
            else {
                return .disallowed
            }

            return .allowed(RegistrationMode.ChangeNumberParams(
                oldE164: localE164,
                oldAuthToken: authToken,
                localAci: registeredState.localIdentifiers.aci,
                localDeviceId: localDeviceId,
            ))
        }
    }

    private func changePhoneNumber(_ params: RegistrationMode.ChangeNumberParams) {
        let logger = PrefixedLogger(prefix: "[ChangeNum]")
        logger.info("Attempting to start change number from settings")
        let dependencies = RegistrationCoordinatorDependencies.from(NSObject())
        let desiredMode = RegistrationMode.changingNumber(params)
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        let coordinator = SSKEnvironment.shared.databaseStorageRef.write {
            return loader.coordinator(
                forDesiredMode: desiredMode,
                transaction: $0,
                logger: logger,
            )
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator)
        let window: UIWindow = CurrentAppContext().mainWindow!
        window.rootViewController = navController
    }

    // MARK: - Two-Factor Authentication

    private func didSelectSetUpAuthenticatorApp() async throws {
        let totp = try await TOTP.generatePendingKey(
            accountEntropyPool: getAccountEntropyPool(),
            dateProvider: dateProvider,
            serviceProvider: serviceProvider,
        )
        let navigationController = OWSNavigationController()
        navigationController.viewControllers = [AuthenticatorAppNameViewController(
            onContinue: { [weak self, weak navigationController] name in
                guard let self, let navigationController else { return }
                self.showAuthenticatorAppSetup(
                    name: name,
                    totp: totp,
                    in: navigationController,
                )
            },
            onCancel: { [weak navigationController] in
                navigationController?.dismiss(animated: true)
            },
        )]
        presentFormSheet(navigationController, animated: true)
    }

    private func showAuthenticatorAppSetup(
        name: String,
        totp: TOTP,
        in navigationController: UINavigationController,
    ) {
        let provisioningURL: URL
        do {
            provisioningURL = try totp.authUrl()
        } catch {
            return
                // TODO[#less]: Print an error
        }

        let setupViewController = AuthenticatorAppSetupViewController(
            setupKey: totp.encodedKey,
            provisioningURL: provisioningURL,
            onContinue: { [weak self, weak navigationController] in
                guard let self, let navigationController else { return }
                let codeViewController = AuthenticatorAppCodeViewController(
                    digitCount: totp.digitCount,
                    validateCode: {
                        try await totp.confirmKey(name: name, code: Int($0))
                    },
                    onVerified: { [weak self] method in
                        self?.didFinishAuthenticatorAppSetup(method: method)
                    },
                )
                navigationController.pushViewController(codeViewController, animated: true)
            },
        )
        navigationController.pushViewController(setupViewController, animated: true)
    }

    private func didFinishAuthenticatorAppSetup(method: ConfirmedMfaKey) {
        // TODO[#less]: Push the 'set name controller' instead of dismissing
        navigationController?.dismiss(animated: true)
        Task {
            loadMfaState()
        }
    }

    private func didSelectSetUpWebAuthn() {
        navigationController?.pushViewController(
            PasskeyEducationViewController { [weak self] in
                guard let self else { return }
                let webAuthn = WebAuthn(
                    accountEntropyPool: getAccountEntropyPool(),
                    dateProvider: dateProvider,
                    serviceProvider: serviceProvider,
                )
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        let method = try await webAuthn.setup()
                        loadMfaState()
                        showRenameTwoFactorMethod(accountEntropyPool: getAccountEntropyPool(), method: method)
                    } catch {
                        Logger.error("Failed! \(error)")
                        // TODO[#less]: Display the error to the user.
                    }
                }
            },
            animated: true,
        )
    }

    private func showRenameTwoFactorMethod(
        accountEntropyPool: SignalServiceKit.AccountEntropyPool,
        method: ConfirmedMfaKey,
    ) {
        let alert = UIAlertController(
            title: OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_METHODS_RENAME_TITLE",
                comment: "Title for the alert to rename a two-factor authentication method.",
            ),
            message: nil,
            preferredStyle: .alert,
        )
        alert.addTextField { textField in
            textField.text = method.metadata?.name
            textField.placeholder = OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_METHODS_NAME_PLACEHOLDER",
                comment: "Placeholder for the field where the user names a two-factor authentication method.",
            )
            textField.autocapitalizationType = .words
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: CommonStrings.cancelButton, style: .cancel))
        alert.addAction(UIAlertAction(title: CommonStrings.saveButton, style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty, name != method.metadata?.name else { return }
            Task {
                do {
                    try await self.serviceProvider.withAuthService(.accounts) {
                        try await $0.setMfaKeyMetadata(
                            for: method.id,
                            metadata: MfaMetadata(
                                name: name,
                                createdAt: method.metadata?.createdAt ?? Date(),
                            ),
                            svrKey: accountEntropyPool.getMasterKey().asSvrKey,
                        )
                    }
                    self.loadMfaState()
                } catch {
                    // TODO[#less]: Report the error to the user
                    Logger.error("Failed to rename MFA method: \(error)")
                }
            }
        })
        present(alert, animated: true)
    }

    private func showRemoveTwoFactorMethod(_ method: ConfirmedMfaKey) {
        let actionSheet = ActionSheetController(
            title: String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_METHODS_REMOVE_CONFIRMATION_TITLE_FORMAT",
                    comment: "Title for the sheet confirming removal of a two-factor authentication method. Embeds {{the method's name}}.",
                ),
                method.metadata?.name ?? CommonStrings.unknownValue,
            ),
            message: OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_METHODS_REMOVE_CONFIRMATION_MESSAGE",
                comment: "Message for the sheet confirming removal of a two-factor authentication method.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_METHODS_REMOVE",
                comment: "Menu option to remove a two-factor authentication method.",
            ),
            style: .destructive,
        ) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await serviceProvider.withAuthService(.accounts) {
                        try await $0.removeMfaKey(id: method.id)
                    }
                    self.loadMfaState()
                } catch {
                    Logger.error("Failed to remove MFA method: \(error)")
                    // TODO[#less]: Report the error to the user
                }
            }
        })
        actionSheet.addAction(.cancel)
        presentActionSheet(actionSheet)
    }

    // MARK: - PINs

    private func didTogglePINRemindersEnabled(_ sender: UISwitch) {
        if sender.isOn {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.ows2FAManagerRef.setAreRemindersEnabled(true, transaction: transaction)
            }
        } else {
            let pinConfirmationVC = PinConfirmationViewController(
                title: OWSLocalizedString(
                    "SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_TITLE",
                    comment: "The title for the dialog asking user to confirm their PIN to disable reminders",
                ),
                explanation: OWSLocalizedString(
                    "SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_EXPLANATION",
                    comment: "The explanation for the dialog asking user to confirm their PIN to disable reminders",
                ),
                actionText: OWSLocalizedString(
                    "SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_ACTION",
                    comment: "The button text for the dialog asking user to confirm their PIN to disable reminders",
                ),
            ) { [weak self] confirmed in
                guard let self else { return }
                if confirmed {
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        SSKEnvironment.shared.ows2FAManagerRef.setAreRemindersEnabled(false, transaction: transaction)
                    }

                    NotificationCenter.default.post(name: .megaphoneStateDidChange, object: nil)
                } else {
                    self.updateTableContents()
                }
            }
            present(pinConfirmationVC, animated: true)
        }
    }

    private func didToggleRegistrationLockV2Enabled(_ sender: UISwitch) {
        let shouldBeEnabled = sender.isOn

        guard shouldBeEnabled != SSKEnvironment.shared.ows2FAManagerRef.isRegistrationLockV2Enabled else { return }

        let actionSheet: ActionSheetController
        if shouldBeEnabled {
            actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "SETTINGS_REGISTRATION_LOCK_TURN_ON_TITLE",
                    comment: "Title for the alert confirming that the user wants to turn on registration lock.",
                ),
                message: OWSLocalizedString(
                    "SETTINGS_REGISTRATION_LOCK_TURN_ON_MESSAGE",
                    comment: "Body for the alert confirming that the user wants to turn on registration lock.",
                ),
            )

            let turnOnAction = ActionSheetAction(title: OWSLocalizedString(
                "SETTINGS_REGISTRATION_LOCK_TURN_ON",
                comment: "Action to turn on registration lock",
            )) { _ in
                guard SSKEnvironment.shared.ows2FAManagerRef.isPinEnabledWithSneakyTransaction else {
                    OWSActionSheets.showActionSheet(
                        message: OWSLocalizedString(
                            "SETTINGS_REGISTRATION_LOCK_TURN_ON_ERROR_PIN_REQUIRED",
                            comment: "Message shown in an action sheet when attempting to enable registration lock, but the user does not have a PIN.",
                        ),
                        fromViewController: self,
                    )
                    self.updateTableContents()
                    return
                }

                Task {
                    do {
                        try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                            from: self,
                            title: CommonStrings.updatingModal,
                        ) {
                            try await SSKEnvironment.shared.ows2FAManagerRef.enableRegistrationLock()
                        }
                    } catch where error.isNetworkFailureOrTimeout {
                        owsFailDebug("Network error enabling reglock.")

                        OWSActionSheets.showActionSheet(
                            message: OWSLocalizedString(
                                "SETTINGS_REGISTRATION_LOCK_TURN_ON_ERROR_NETWORK",
                                comment: "Message shown in an action sheet when attempting to enable registration lock, but encountering a network error.",
                            ),
                            fromViewController: self,
                        )
                    } catch {
                        owsFailDebug("Failed to enable reglock! \(error)")

                        OWSActionSheets.showContactSupportActionSheet(
                            message: OWSLocalizedString(
                                "SETTINGS_REGISTRATION_LOCK_TURN_ON_ERROR_GENERIC",
                                comment: "Message shown in an action sheet when attempting to enable registration lock, but encountering a generic error.",
                            ),
                            emailFilter: .custom("RegLockEnableFailure"),
                            fromViewController: self,
                        )
                    }

                    self.updateTableContents()
                }
            }
            actionSheet.addAction(turnOnAction)
        } else {
            actionSheet = ActionSheetController(title: OWSLocalizedString(
                "SETTINGS_REGISTRATION_LOCK_TURN_OFF_TITLE",
                comment: "Title for the alert confirming that the user wants to turn off registration lock.",
            ))

            let turnOffAction = ActionSheetAction(
                title: OWSLocalizedString(
                    "SETTINGS_REGISTRATION_LOCK_TURN_OFF",
                    comment: "Action to turn off registration lock",
                ),
                style: .destructive,
            ) { _ in
                Task {
                    do {
                        try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                            from: self,
                            title: CommonStrings.updatingModal,
                        ) {
                            try await SSKEnvironment.shared.ows2FAManagerRef.disableRegistrationLock()
                        }
                    } catch where error.isNetworkFailureOrTimeout {
                        owsFailDebug("Network error disabling reglock.")

                        OWSActionSheets.showActionSheet(
                            message: OWSLocalizedString(
                                "SETTINGS_REGISTRATION_LOCK_TURN_OFF_ERROR_NETWORK",
                                comment: "Message shown in an action sheet when attempting to enable registration lock, but encountering a network error.",
                            ),
                            fromViewController: self,
                        )
                    } catch {
                        owsFailDebug("Failed to disable reglock! \(error)")

                        OWSActionSheets.showContactSupportActionSheet(
                            message: OWSLocalizedString(
                                "SETTINGS_REGISTRATION_LOCK_TURN_OFF_ERROR_GENERIC",
                                comment: "Message shown in an action sheet when attempting to enable registration lock, but encountering a generic error.",
                            ),
                            emailFilter: .custom("RegLockDisableFailure"),
                            fromViewController: self,
                        )
                    }

                    self.updateTableContents()
                }
            }
            actionSheet.addAction(turnOffAction)
        }

        let cancelAction = ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
        ) { _ in
            self.updateTableContents()
        }
        actionSheet.addAction(cancelAction)

        presentActionSheet(actionSheet)
    }

    // MARK: -

    private func showChangePin() {
        let vc = PinSetupViewController(mode: .changing) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.popToViewController(self, animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showCreatePin() {
        let vc = PinSetupViewController(
            mode: .creating,
        ) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.popToViewController(self, animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func getAccountEntropyPool() -> SignalServiceKit.AccountEntropyPool {
        return context.db.read {
            guard let accountEntropyPool = DependenciesBridge.shared.accountKeyStore.getAccountEntropyPool(tx: $0) else {
                // This should be impossible; the only times you don't have
                // an AEP are during registration.
                owsFail("Can't provision without account entropy pool.")
            }
            return accountEntropyPool
        }
    }
}
