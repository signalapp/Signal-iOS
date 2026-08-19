//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AccountSettingsViewController: OWSTableViewController2 {

    private let appReadiness: AppReadinessSetter
    private let context: ViewControllerContext

    init(appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
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
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        // Show the change pin and reglock sections
        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice {
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

        let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction

        if tsRegistrationState.isDeregistered {
            let accountSection = OWSTableSection()
            accountSection.headerTitle = accountSettingsTitle
            accountSection.add(.actionItem(
                withText: tsRegistrationState.isPrimaryDevice ?? true
                    ? OWSLocalizedString("SETTINGS_REREGISTER_BUTTON", comment: "Label for re-registration button.")
                    : OWSLocalizedString("SETTINGS_RELINK_BUTTON", comment: "Label for re-link button."),
                textColor: .ows_accentBlue,
                actionBlock: { [weak self] in
                    self?.reregisterUser()
                },
            ))
            accountSection.add(.actionItem(
                withText: OWSLocalizedString(
                    "SETTINGS_DELETE_DATA_BUTTON",
                    comment: "Label for 'delete data' button.",
                ),
                textColor: .ows_accentRed,
                actionBlock: { [weak self] in
                    self?.deleteUnregisteredUserData()
                },
            ))
            contents.add(accountSection)
        } else if tsRegistrationState.isRegisteredPrimaryDevice {
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
                textColor: .ows_accentRed,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_account"),
                actionBlock: { [weak self] in
                    self?.unregisterUser()
                },
            ))
            contents.add(accountSection)
        } else {
            if tsRegistrationState.isRegistered {
                let cardSection = OWSTableSection()
                cardSection.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }
                    return self.linkedDeviceCardCell()
                }))
                contents.add(cardSection)
            }

            addDeleteLocalDataSection(to: contents)
        }

        self.contents = contents
    }

    // MARK: - Section contents

    private func addDeleteLocalDataSection(to contents: OWSTableContents) {
        let deleteSection = OWSTableSection()
        deleteSection.add(.actionItem(
            withText: OWSLocalizedString(
                "SETTINGS_LINKED_DEVICE_DELETE_DATA_BUTTON",
                comment: "Label for a button that deletes all Signal data from a linked device.",
            ),
            textColor: .Signal.red,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_data"),
            actionBlock: { [weak self] in
                self?.deleteLinkedData()
            },
        ))
        deleteSection.footerTitle = OWSLocalizedString(
            "SETTINGS_LINKED_DEVICE_DELETE_DATA_FOOTER",
            comment: "Footer below the 'delete app data' button, shown on a linked device's account settings.",
        )
        contents.add(deleteSection)
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

    private func reregisterUser() {
        RegistrationUtils.showReregistrationUI(fromViewController: self, appReadiness: appReadiness)
    }

    private func deleteLinkedData() {
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

    private func unregisterUser() {
        let vc = DeleteAccountConfirmationViewController(appReadiness: appReadiness)
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

    enum ChangeNumberState {
        case disallowed
        case allowed(RegistrationMode.ChangeNumberParams)
    }

    private func changeNumberState() -> ChangeNumberState {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction -> ChangeNumberState in
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
        let navController = RegistrationNavigationController.withCoordinator(coordinator, appReadiness: appReadiness)
        let window: UIWindow = CurrentAppContext().mainWindow!
        window.rootViewController = navController
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
                            try await SSKEnvironment.shared.ows2FAManagerRef.enableRegistrationLockV2(logger: PrefixedLogger(prefix: "[Settings]"))
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
                            try await SSKEnvironment.shared.ows2FAManagerRef.disableRegistrationLockV2()
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
}
