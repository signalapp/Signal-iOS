//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class DeleteAccountConfirmationViewController: OWSTableViewController2 {
    private var callingCode = "+1"
    private var countryCode = "US"
    private let phoneNumberTextField = UITextField()
    private let nameLabel = UILabel()

    // Don't allow swipe to dismiss
    override var isModalInPresentation: Bool {
        get { true }
        set {}
    }

    override func loadView() {
        view = UIView()

        phoneNumberTextField.returnKeyType = .done
        phoneNumberTextField.autocorrectionType = .no
        phoneNumberTextField.spellCheckingType = .no

        phoneNumberTextField.delegate = self
        phoneNumberTextField.accessibilityIdentifier = "phone_number_textfield"
    }

    override func viewDidLoad() {
        shouldAvoidKeyboard = true

        super.viewDidLoad()

        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .cancel, target: self, action: #selector(didTapCancel))
        navigationItem.rightBarButtonItem = .init(title: CommonStrings.deleteButton, style: .done, target: self, action: #selector(didTapDelete))
        navigationItem.rightBarButtonItem?.setTitleTextAttributes([.foregroundColor: UIColor.ows_accentRed], for: .normal)

        populateDefaultCountryCode()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        phoneNumberTextField.becomeFirstResponder()
    }

    override func themeDidChange() {
        super.themeDidChange()
        nameLabel.textColor = Theme.primaryTextColor
        phoneNumberTextField.textColor = Theme.primaryTextColor
        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            return self.buildHeaderCell()
        }))
        contents.add(headerSection)

        let confirmSection = OWSTableSection()
        confirmSection.headerTitle = OWSLocalizedString(
            "DELETE_ACCOUNT_CONFIRMATION_SECTION_TITLE",
            comment: "Section header"
        )

        confirmSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "DELETE_ACCOUNT_CONFIRMATION_COUNTRY_CODE_TITLE",
                comment: "Title for the 'country code' row of the 'delete account confirmation' view controller."
            ),
            detailText: "\(callingCode) (\(countryCode))",
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let countryCodeController = CountryCodeViewController()
                countryCodeController.countryCodeDelegate = self
                self.present(OWSNavigationController(rootViewController: countryCodeController), animated: true)
            }
        ))
        confirmSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            return self.phoneNumberCell
        },
            actionBlock: { [weak self] in
                self?.phoneNumberTextField.becomeFirstResponder()
            }
        ))
        contents.add(confirmSection)

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

        let titleLabel = UILabel()
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.text = OWSLocalizedString(
            "DELETE_ACCOUNT_CONFIRMATION_TITLE",
            comment: "Title for the 'delete account' confirmation view."
        )

        let descriptionLabel = UILabel()
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.font = .dynamicTypeSubheadline
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.textAlignment = .center
        descriptionLabel.text = OWSLocalizedString(
            "DELETE_ACCOUNT_CONFIRMATION_DESCRIPTION",
            comment: "Description for the 'delete account' confirmation view."
        )

        let headerView = UIStackView(arrangedSubviews: [
            imageContainer,
            titleLabel,
            descriptionLabel
        ])
        headerView.axis = .vertical
        headerView.spacing = 12

        let cell = OWSTableItem.newCell()
        cell.contentView.addSubview(headerView)
        headerView.autoPinEdgesToSuperviewMargins()
        return cell
    }

    lazy var phoneNumberCell: UITableViewCell = {
        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        nameLabel.text = OWSLocalizedString(
            "DELETE_ACCOUNT_CONFIRMATION_PHONE_NUMBER_TITLE",
            comment: "Title for the 'phone number' row of the 'delete account confirmation' view controller."
        )
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.font = OWSTableItem.primaryLabelFont
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.autoSetDimension(.height, toSize: 24, relation: .greaterThanOrEqual)

        phoneNumberTextField.textColor = Theme.primaryTextColor
        phoneNumberTextField.font = OWSTableItem.accessoryLabelFont
        phoneNumberTextField.placeholder = TextFieldFormatting.examplePhoneNumber(
            forCountryCode: countryCode,
            callingCode: callingCode,
            includeExampleLabel: false
        )

        nameLabel.setCompressionResistanceHigh()
        phoneNumberTextField.setContentHuggingHorizontalHigh()

        let contentRow = UIStackView(arrangedSubviews: [
            nameLabel, phoneNumberTextField
        ])
        contentRow.spacing = OWSTableItem.iconSpacing
        contentRow.alignment = .center
        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        return cell
    }()

    @objc
    private func didTapDelete() {
        guard hasEnteredLocalNumber else {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "DELETE_ACCOUNT_CONFIRMATION_WRONG_NUMBER",
                    comment: "Title for the action sheet when you enter the wrong number on the 'delete account confirmation' view controller."
                )
            )
            return
        }

        guard reachabilityManager.isReachable else {
            OWSActionSheets.showActionSheet(
                title: OWSLocalizedString(
                    "DELETE_ACCOUNT_CONFIRMATION_NO_INTERNET",
                    comment: "Title for the action sheet when you have no internet on the 'delete account confirmation' view controller."
                )
            )
            return
        }

        phoneNumberTextField.resignFirstResponder()

        showDeletionConfirmUI_checkPayments()
    }

    private func showDeletionConfirmUI_checkPayments() {
        if self.paymentsHelper.arePaymentsEnabled,
           let paymentBalance = self.paymentsSwift.currentPaymentBalance,
           !paymentBalance.amount.isZero {
            showDeleteAccountPaymentsConfirmationUI(paymentBalance: paymentBalance.amount)
        } else {
            showDeletionConfirmUI()
        }
    }

    private func showDeleteAccountPaymentsConfirmationUI(paymentBalance: TSPaymentAmount) {
        let title = OWSLocalizedString(
            "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_TITLE",
            comment: "Title for the alert confirming whether the user wants transfer their payments balance before deleting their account.")

        let formattedBalance = PaymentsFormat.format(paymentAmount: paymentBalance,
                                                     isShortForm: false,
                                                     withCurrencyCode: true,
                                                     withSpace: true)
        let messageFormat = OWSLocalizedString(
            "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_MESSAGE_FORMAT",
            comment: "Body for the alert confirming whether the user wants transfer their payments balance before deleting their account. Embeds: {{ the current payment balance }}.")
        let message = String(format: messageFormat, formattedBalance)

        let actionSheet = ActionSheetController( title: title, message: message)

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString(
                                                    "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_TRANSFER",
                                                    comment: "Button for transferring the user's payments balance before deleting their account."),
                                                style: .default
        ) { [weak self] _ in
            self?.transferPaymentsButton()
        })

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString(
                                                    "SETTINGS_DELETE_ACCOUNT_PAYMENTS_BALANCE_ALERT_DONT_TRANSFER",
                                                    comment: "Button for to _not_ transfer the user's payments balance before deleting their account."),
                                                style: .destructive
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
                comment: "Title for the action sheet confirmation title of the 'delete account confirmation' view controller."
            ),
            message: OWSLocalizedString(
                "DELETE_ACCOUNT_CONFIRMATION_ACTION_SHEEET_MESSAGE",
                comment: "Title for the action sheet message of the 'delete account confirmation' view controller."
            ),
            proceedTitle: OWSLocalizedString(
                "DELETE_ACCOUNT_CONFIRMATION_ACTION_SHEEET_ACTION",
                comment: "Title for the action sheet 'delete' action of the 'delete account confirmation' view controller."
            ),
            proceedStyle: .destructive
        ) { _ in
            let overlayView = UIView()
            overlayView.backgroundColor = self.tableBackgroundColor.withAlphaComponent(0.9)
            overlayView.alpha = 0
            self.navigationController?.view.addSubview(overlayView)
            overlayView.autoPinEdgesToSuperviewEdges()

            let progressView = AnimatedProgressView(
                loadingText: OWSLocalizedString(
                    "DELETE_ACCOUNT_CONFIRMATION_IN_PROGRESS",
                    comment: "Indicates the work we are doing while deleting the account"
                )
            )
            self.navigationController?.view.addSubview(progressView)
            progressView.autoCenterInSuperview()

            progressView.startAnimating { overlayView.alpha = 1 }

            firstly {
                self.deleteSubscriptionIfNecessary()
            }.then {
                self.unregisterAccount()
            }.done {
                // We don't need to stop animating here because "resetAppData" exits the app.
                SignalApp.resetAppDataWithUI()
            }.catch { error in
                owsFailDebug("Failed to unregister \(error)")

                progressView.stopAnimating(success: false) {
                    overlayView.alpha = 0
                } completion: {
                    overlayView.removeFromSuperview()
                    progressView.removeFromSuperview()

                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "DELETE_ACCOUNT_CONFIRMATION_DELETE_FAILED",
                            comment: "Title for the action sheet when delete failed on the 'delete account confirmation' view controller."
                        )
                    )
                }
            }
        }
    }

    private func deleteSubscriptionIfNecessary() -> Promise<Void> {
        let activeSubscriptionId = databaseStorage.read {
            SubscriptionManagerImpl.getSubscriberID(transaction: $0)
        }
        if let activeSubscriptionId = activeSubscriptionId {
            Logger.info("Found subscriber ID. Canceling subscription...")
            return SubscriptionManagerImpl.cancelSubscription(for: activeSubscriptionId)
        } else {
            return Promise.value(())
        }
    }

    private func unregisterAccount() -> Promise<Void> {
        Logger.info("Unregistering...")
        return Promise.wrapAsync {
            try await DependenciesBridge.shared.registrationStateChangeManager.unregisterFromService(auth: .implicit())
        }
    }

    var hasEnteredLocalNumber: Bool {
        guard let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber else {
            owsFailDebug("local number unexpectedly nil")
            return false
        }

        guard let phoneNumberText = phoneNumberTextField.text else { return false }

        let possiblePhoneNumber = callingCode + phoneNumberText
        let possibleNumbers = PhoneNumber.tryParsePhoneNumbers(
            fromUserSpecifiedText: possiblePhoneNumber,
            clientPhoneNumber: localNumber
        ).map { $0.toE164() }

        return possibleNumbers.contains(localNumber)
    }

    @objc
    private func didTapCancel() {
        dismiss(animated: true)
    }
}

extension DeleteAccountConfirmationViewController: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController,
                                          didSelectCountry countryState: RegistrationCountryState) {
        updateCountry(callingCode: countryState.callingCode,
                      countryCode: countryState.countryCode)
    }

    func populateDefaultCountryCode() {
        guard let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber else {
            return owsFailDebug("Local number unexpectedly nil")
        }

        var callingCodeInt: Int?
        var countryCode: String?

        if let localE164 = PhoneNumber(fromE164: localNumber), let localCountryCode = localE164.getCountryCode()?.intValue {
            callingCodeInt = localCountryCode
        } else {
            callingCodeInt = phoneNumberUtil.getCountryCode(
                forRegion: PhoneNumber.defaultCountryCode()
            ).intValue
        }

        var callingCode: String?
        if let callingCodeInt = callingCodeInt {
            callingCode = COUNTRY_CODE_PREFIX + "\(callingCodeInt)"
            countryCode = phoneNumberUtil.probableCountryCode(forCallingCode: callingCode!)
        }

        updateCountry(callingCode: callingCode, countryCode: countryCode)
    }

    func updateCountry(callingCode: String?, countryCode: String?) {
        guard let callingCode = callingCode, !callingCode.isEmpty, let countryCode = countryCode, !countryCode.isEmpty else {
            return owsFailDebug("missing calling code for selected country")
        }

        self.callingCode = callingCode
        self.countryCode = countryCode
        updateTableContents()
    }
}

extension DeleteAccountConfirmationViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapDelete()
        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldFormatting.phoneNumberTextField(textField, changeCharactersIn: range, replacementString: string, callingCode: callingCode)
        return false
    }
}
