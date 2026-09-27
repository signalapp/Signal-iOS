//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class DeleteAccountConfirmationViewController: OWSTableViewController2 {
    private var phoneNumberCountry: PhoneNumberCountry?

    private let registeredStateAtStart: RegisteredState

    init(registeredState: RegisteredState) {
        self.registeredStateAtStart = registeredState
    }

    private lazy var nationalNumberTextField = UITextField()

    // Don't allow swipe to dismiss
    override var isModalInPresentation: Bool {
        get { true }
        set {}
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if registeredStateAtStart.localIdentifiers.phoneNumberAsOptional != nil {
            shouldAvoidKeyboard = true
        }

        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        navigationItem.rightBarButtonItem = .prominentButton(title: CommonStrings.deleteButton) { [weak self] in
            self?.didTapDelete()
        }
        if #available(iOS 26, *) {
            navigationItem.rightBarButtonItem?.tintColor = .Signal.red
        } else {
            navigationItem.rightBarButtonItem?.setTitleTextAttributes(
                [.foregroundColor: UIColor.Signal.red],
                for: .normal,
            )
        }

        if let phoneNumber = registeredStateAtStart.localIdentifiers.phoneNumberAsOptional {
            populateDefaultPhoneNumberCountry(phoneNumber: phoneNumber)
        }
        updateTableContents()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        if registeredStateAtStart.localIdentifiers.phoneNumberAsOptional != nil {
            nationalNumberTextField.becomeFirstResponder()
        }
    }

    fileprivate func updateTableContents() {
        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.add(.init(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            return self.buildHeaderCell()
        }))
        contents.add(headerSection)

        if let phoneNumberCountry {
            let confirmSection = OWSTableSection()
            confirmSection.headerTitle = OWSLocalizedString(
                "DELETE_ACCOUNT_CONFIRMATION_SECTION_TITLE",
                comment: "Section header",
            )

            confirmSection.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "DELETE_ACCOUNT_CONFIRMATION_COUNTRY_CODE_TITLE",
                    comment: "Title for the 'country code' row of the 'delete account confirmation' view controller.",
                ),
                accessoryText: "\(phoneNumberCountry.plusPrefixedCallingCode) (\(phoneNumberCountry.countryCode))",
                actionBlock: { [weak self] in
                    guard let self else { return }
                    let countryCodeController = CountryCodeViewController(delegate: self)
                    self.present(OWSNavigationController(rootViewController: countryCodeController), animated: true)
                },
            ))
            confirmSection.add(.init(
                customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }
                    return self.buildPhoneNumberCell(phoneNumberCountry: phoneNumberCountry)
                },
                actionBlock: { [weak self] in
                    self?.nationalNumberTextField.becomeFirstResponder()
                },
            ))
            contents.add(confirmSection)
        }

        self.contents = contents
    }

    func buildHeaderCell() -> UITableViewCell {
        let imageView = UIImageView(image: Theme.isDarkThemeEnabled ? #imageLiteral(resourceName: "delete-account-dark") : #imageLiteral(resourceName: "delete-account-light"))
        imageView.autoSetDimensions(to: CGSize(square: 112))
        let imageContainer = UIView()
        imageContainer.addSubview(imageView)
        imageView.autoPinEdge(toSuperviewEdge: .top)
        imageView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 12)
        imageView.autoHCenterInSuperview()

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "DELETE_ACCOUNT_CONFIRMATION_TITLE",
            comment: "Title for the 'delete account' confirmation view.",
        ))

        let descriptionLabel = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "DELETE_ACCOUNT_CONFIRMATION_DESCRIPTION",
            comment: "Description for the 'delete account' confirmation view.",
        ))

        let headerView = UIStackView(arrangedSubviews: [
            imageContainer,
            titleLabel,
            descriptionLabel,
        ])
        headerView.axis = .vertical
        headerView.spacing = 12

        let cell = OWSTableItem.newCell()
        cell.contentView.addSubview(headerView)
        headerView.autoPinEdgesToSuperviewMargins()
        return cell
    }

    private var phoneNumberCell: UITableViewCell?

    private func buildPhoneNumberCell(phoneNumberCountry: PhoneNumberCountry) -> UITableViewCell {
        if let phoneNumberCell {
            return phoneNumberCell
        } else {
            let result = _buildPhoneNumberCell(phoneNumberCountry: phoneNumberCountry)
            self.phoneNumberCell = result
            return result
        }
    }

    private func _buildPhoneNumberCell(phoneNumberCountry: PhoneNumberCountry) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        let nameLabel = UILabel()
        nameLabel.text = OWSLocalizedString(
            "DELETE_ACCOUNT_CONFIRMATION_PHONE_NUMBER_TITLE",
            comment: "Title for the 'phone number' row of the 'delete account confirmation' view controller.",
        )
        nameLabel.textColor = .Signal.label
        nameLabel.font = OWSTableItem.primaryLabelFont
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.autoSetDimension(.height, toSize: 24, relation: .greaterThanOrEqual)

        let nationalNumberTextField = self.nationalNumberTextField
        nationalNumberTextField.returnKeyType = .done
        nationalNumberTextField.autocorrectionType = .no
        nationalNumberTextField.spellCheckingType = .no
        nationalNumberTextField.keyboardType = .phonePad
        nationalNumberTextField.textColor = .Signal.label
        nationalNumberTextField.delegate = self
        nationalNumberTextField.font = OWSTableItem.accessoryLabelFont
        nationalNumberTextField.placeholder = TextFieldFormatting.exampleNationalNumber(
            forCountryCode: phoneNumberCountry.countryCode,
            includeExampleLabel: false,
        )

        nameLabel.setCompressionResistanceHigh()
        nationalNumberTextField.setContentHuggingHorizontalHigh()

        let contentRow = UIStackView(arrangedSubviews: [
            nameLabel,
            nationalNumberTextField,
        ])
        contentRow.spacing = OWSTableItem.iconSpacing
        contentRow.alignment = .center
        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        return cell
    }

    private func didTapDelete() {
        if let phoneNumber = registeredStateAtStart.localIdentifiers.phoneNumberAsOptional {
            guard hasEnteredLocalNumber(phoneNumber: phoneNumber) else {
                OWSActionSheets.showActionSheet(
                    title: OWSLocalizedString(
                        "DELETE_ACCOUNT_CONFIRMATION_WRONG_NUMBER",
                        comment: "Title for the action sheet when you enter the wrong number on the 'delete account confirmation' view controller.",
                    ),
                )
                return
            }
        }

        guard SSKEnvironment.shared.reachabilityManagerRef.isReachable else {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "DELETE_ACCOUNT_CONFIRMATION_NO_INTERNET",
                    comment: "Title for the action sheet when you have no internet on the 'delete account confirmation' view controller.",
                ),
            )
            return
        }

        if registeredStateAtStart.localIdentifiers.phoneNumberAsOptional != nil {
            nationalNumberTextField.resignFirstResponder()
        }

        showDeletionConfirmUI_checkPayments()
    }

    private func showDeletionConfirmUI_checkPayments() {
        if
            SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled,
            let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance,
            !paymentBalance.amount.isZero
        {
            showDeleteAccountPaymentsConfirmationUI(paymentBalance: paymentBalance.amount)
        } else {
            showDeletionConfirmUI()
        }
    }

    private func showDeleteAccountPaymentsConfirmationUI(paymentBalance: TSPaymentAmount) {
        let title = OWSLocalizedString(
            "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_TITLE",
            comment: "Title for the alert confirming whether the user wants transfer their payments balance before deleting their account.",
        )

        let formattedBalance = PaymentsFormat.format(
            paymentAmount: paymentBalance,
            isShortForm: false,
            withCurrencyCode: true,
            withSpace: true,
        )
        let messageFormat = OWSLocalizedString(
            "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_MESSAGE_FORMAT",
            comment: "Body for the alert confirming whether the user wants transfer their payments balance before deleting their account. Embeds: {{ the current payment balance }}.",
        )
        let message = String.nonPluralLocalizedStringWithFormat(messageFormat, formattedBalance)

        let actionSheet = ActionSheetController(title: title, message: message)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_TRANSFER",
                comment: "Button for transferring the user's payments balance before deleting their account.",
            ),
            style: .default,
        ) { [weak self] _ in
            self?.transferPaymentsButton()
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_DONT_TRANSFER",
                comment: "Button for to _not_ transfer the user's payments balance before deleting their account.",
            ),
            style: .destructive,
        ) { [weak self] _ in
            self?.showDeletionConfirmUI()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func transferPaymentsButton() {
        dismiss(animated: true) {
            guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
                owsFailDebug("Could not identify frontmostViewController")
                return
            }
            guard let navigationController = frontmostViewController.navigationController else {
                owsFailDebug("Missing navigationController.")
                return
            }
            var viewControllers = navigationController.viewControllers
            _ = viewControllers.removeLast()
            viewControllers.append(PaymentsSettingsViewController(mode: .inAppSettings))
            viewControllers.append(PaymentsTransferOutViewController(transferAmount: nil))
            navigationController.setViewControllers(viewControllers, animated: true)
        }
    }

    private func showDeletionConfirmUI() {

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "DELETE_ACCOUNT_CONFIRMATION_ACTION_SHEEET_TITLE",
                comment: "Title for the action sheet confirmation title of the 'delete account confirmation' view controller.",
            ),
            message: OWSLocalizedString(
                "DELETE_ACCOUNT_CONFIRMATION_ACTION_SHEEET_MESSAGE",
                comment: "Title for the action sheet message of the 'delete account confirmation' view controller.",
            ),
            proceedTitle: OWSLocalizedString(
                "DELETE_ACCOUNT_CONFIRMATION_ACTION_SHEEET_ACTION",
                comment: "Title for the action sheet 'delete' action of the 'delete account confirmation' view controller.",
            ),
            proceedStyle: .destructive,
            proceedAction: { [weak self] _ in self?.deleteAccount() },
        )
    }

    private func deleteAccount() {
        Task {
            let overlayView = UIView()
            overlayView.backgroundColor = self.tableBackgroundColor.withAlphaComponent(0.9)
            overlayView.alpha = 0
            self.navigationController?.view.addSubview(overlayView)
            overlayView.autoPinEdgesToSuperviewEdges()

            let progressView = AnimatedProgressView(
                loadingText: OWSLocalizedString(
                    "DELETE_ACCOUNT_CONFIRMATION_IN_PROGRESS",
                    comment: "Indicates the work we are doing while deleting the account",
                ),
            )
            self.navigationController?.view.addSubview(progressView)
            progressView.autoCenterInSuperview()

            progressView.startAnimating { overlayView.alpha = 1 }

            do {
                try await { () async throws -> Never in
                    try await self.deleteDonationSubscriptionIfNecessary()
                    try await self.deleteBackupIfNecessary()
                    try await self.leaveGroups()
                    try await self.unregisterAccount()
                    resetAppDataAndExit()
                }()
            } catch {
                owsFailDebug("Failed to delete account! \(error)")

                progressView.stopAnimating(success: false) {
                    overlayView.alpha = 0
                } completion: {
                    overlayView.removeFromSuperview()
                    progressView.removeFromSuperview()

                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "DELETE_ACCOUNT_CONFIRMATION_DELETE_FAILED",
                            comment: "Title for the action sheet when delete failed on the 'delete account confirmation' view controller.",
                        ),
                    )
                }
            }
        }
    }

    private func deleteBackupIfNecessary() async throws {
        let backupKeyService = DependenciesBridge.shared.backupKeyService
        let backupSettingsStore = BackupSettingsStore()
        let db = DependenciesBridge.shared.db
        let logger = PrefixedLogger(prefix: "[Backups]")
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        // Fetch this again in case we got deregistered while the view was visible.
        let registeredState = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()

        let currentBackupPlan = db.read { tx in backupSettingsStore.backupPlan(tx: tx) }

        switch currentBackupPlan {
        case .disabled:
            logger.info("Backups disabled: skipping delete.")
            return
        case .disabling:
            // If we're disabling then BackupDisablingManager is actively trying
            // to delete our remote backup, too. Might as well try here too.
            break
        case .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        logger.info("Attempting to delete Backups!")
        try await backupKeyService.deleteBackupKey(
            localIdentifiers: registeredState.localIdentifiers,
            auth: .implicit(),
            logger: logger,
        )
    }

    private func deleteDonationSubscriptionIfNecessary() async throws {
        let activeSubscriptionId = SSKEnvironment.shared.databaseStorageRef.read {
            DependenciesBridge.shared.donationSubscriptionManager.getSubscriberID(tx: $0)
        }
        guard let activeSubscriptionId else {
            return
        }
        Logger.info("Found subscriber ID. Canceling subscription...")
        return try await DependenciesBridge.shared.donationSubscriptionManager.cancelSubscription(for: activeSubscriptionId)
    }

    private func leaveGroups() async throws {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        var sendUpdatePromises = [Promise<Void>]()
        for uniqueId in databaseStorage.read(block: ThreadFinder().fetchUniqueIds(tx:)) {
            let leavePromise = await databaseStorage.awaitableWrite { tx -> Promise<[Promise<Void>]> in
                guard
                    let thread = TSThread.fetchViaCache(uniqueId: uniqueId, transaction: tx),
                    let groupThread = thread as? TSGroupThread,
                    groupThread.isGroupV2Thread,
                    let groupModel = groupThread.groupModel as? TSGroupModelV2
                else {
                    return .value([])
                }
                if groupModel.groupMembership.isLocalUserRequestingMember {
                    return Promise.wrapAsync {
                        try await GroupManager.cancelRequestToJoin(groupModel: groupModel)
                        // There's no messages to send when canceling a join request because we
                        // don't know who's in the the group/who needs to be notified.
                        return []
                    }
                } else {
                    return GroupManager.localLeaveGroupOrDeclineInvite(
                        groupThread: groupThread,
                        isDeletingAccount: true,
                        tx: tx,
                    )
                }
            }
            do {
                sendUpdatePromises.append(contentsOf: try await leavePromise.awaitable())
            } catch GroupsV2Error.groupBlocked,
                GroupsV2Error.localUserNotInGroup,
                GroupsV2Error.terminatedGroup
            {
                // Can't do anything about these groups; ignore the errors.
            }
        }
        for sendUpdatePromise in sendUpdatePromises {
            do {
                try await sendUpdatePromise.awaitable()
            } catch {
                Logger.warn("Couldn't send group update, but we've already left, so ignoring: \(error)")
            }
        }
    }

    private func unregisterAccount() async throws {
        Logger.info("Unregistering...")
        try await DependenciesBridge.shared.registrationStateChangeManager.unregisterFromService()
    }

    private func resetAppDataAndExit() -> Never {
        let keyFetcher = SSKEnvironment.shared.databaseStorageRef.keyFetcher
        SignalApp.shared.resetAppDataAndExit(keyFetcher: keyFetcher)
    }

    // MARK: -

    private func hasEnteredLocalNumber(phoneNumber: String) -> Bool {
        let phoneNumberCountry = phoneNumberCountry.owsFailUnwrap("must exist when we have a phone number")

        guard let nationalNumber = nationalNumberTextField.text else {
            return false
        }

        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        let parsedNumber = phoneNumberUtil.parsePhoneNumber(
            countryCode: phoneNumberCountry.countryCode,
            nationalNumber: nationalNumber,
        )
        guard let parsedNumber else {
            return false
        }
        return phoneNumber == parsedNumber.e164
    }
}

// MARK: - CountryCodeViewControllerDelegate

extension DeleteAccountConfirmationViewController: CountryCodeViewControllerDelegate {
    func countryCodeViewController(_ vc: CountryCodeViewController, didSelectCountry country: PhoneNumberCountry) {
        updatePhoneNumberCountry(country)
        updateTableContents()
    }

    private func populateDefaultPhoneNumberCountry(phoneNumber: String) {
        let phoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef
        let defaultCountry: PhoneNumberCountry
        let localCountry = PhoneNumberCountry.buildCountry(forCountryCode: phoneNumberUtil.preferredCountryCode(forLocalNumber: phoneNumber))
        if let localCountry {
            defaultCountry = localCountry
        } else {
            owsFailDebug("Couldn't determine local country.")
            defaultCountry = .defaultValue
        }
        updatePhoneNumberCountry(defaultCountry)
    }

    private func updatePhoneNumberCountry(_ phoneNumberCountry: PhoneNumberCountry) {
        self.phoneNumberCountry = phoneNumberCountry
    }
}

// MARK: - UITextFieldDelegate

extension DeleteAccountConfirmationViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapDelete()
        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let phoneNumberCountry = phoneNumberCountry.owsFailUnwrap("must exist when we have a phone number")
        TextFieldFormatting.phoneNumberTextField(textField, changeCharactersIn: range, replacementString: string, plusPrefixedCallingCode: phoneNumberCountry.plusPrefixedCallingCode)
        return false
    }
}
