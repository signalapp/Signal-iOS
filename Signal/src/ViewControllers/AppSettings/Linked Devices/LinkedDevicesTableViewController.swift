//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import LocalAuthentication

// This has a long and awful name so that if the condition is ever changed,
// the text shown to internal users about it can be changed too.
private var shouldShowDeviceIdsBecauseUserIsInternal: Bool { DebugFlags.internalSettings }

private struct DisplayableDevice: Equatable {
    let device: OWSDevice
    let displayName: String

    static func == (lhs: DisplayableDevice, rhs: DisplayableDevice) -> Bool {
        lhs.device.deviceId == rhs.device.deviceId && lhs.device.createdAt == rhs.device.createdAt
    }
}

class LinkedDevicesTableViewController: OWSTableViewController2 {

    private var displayableDevices: [DisplayableDevice] = []

    private var pollingRefreshTimer: Timer?

    private var oldDeviceList: [DisplayableDevice] = []
    private var isExpectingMoreDevices = false {
        didSet {
            shouldShowFinishLinkingSheet = isExpectingMoreDevices
            && FeatureFlags.biometricLinkedDeviceFlow
        }
    }
    private var shouldShowFinishLinkingSheet = false
    private weak var finishLinkingSheet: HeroSheetViewController?

    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("LINKED_DEVICES_TITLE", comment: "Menu item and navbar title for the device manager")

        refreshControl.addTarget(self, action: #selector(refreshDevices), for: .valueChanged)

        tableView.refreshControl = refreshControl

        updateTableContents()

        addObservers()

        updateDeviceList()
    }

    private func addObservers() {
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceListUpdateSucceeded),
                                               name: OWSDevicesService.deviceListUpdateSucceeded,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceListUpdateFailed),
                                               name: OWSDevicesService.deviceListUpdateFailed,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceListUpdateModifiedDeviceList),
                                               name: OWSDevicesService.deviceListUpdateModifiedDeviceList,
                                               object: nil)
    }

    // MARK: -

    private func updateDeviceList() {
        AssertIsOnMainThread()

        displayableDevices = SSKEnvironment.shared.databaseStorageRef.read { transaction -> [DisplayableDevice] in
            let justDevices = OWSDevice.anyFetchAll(transaction: transaction).filter {
                !$0.isPrimaryDevice
            }

            let identityManager = DependenciesBridge.shared.identityManager
            return justDevices.map { device -> DisplayableDevice in
                return .init(
                    device: device,
                    displayName: device.displayName(
                        identityManager: identityManager,
                        tx: transaction.asV2Read
                    )
                )
            }
        }

        displayableDevices.sort { (lhs, rhs) in
            lhs.device.createdAt < rhs.device.createdAt
        }

        if displayableDevices.isEmpty {
            self.isEditing = false
        }

        updateNavigationItems()
        updateTableContents()

        if oldDeviceList != displayableDevices {
            if
                isExpectingMoreDevices,
                let newDevice = displayableDevices.last,
                newDevice != oldDeviceList.last
            {
                if let finishLinkingSheet {
                    finishLinkingSheet.dismiss(animated: true) {
                        self.showNewDeviceToast(deviceName: newDevice.displayName)
                    }
                } else {
                    showNewDeviceToast(deviceName: newDevice.displayName)
                }
                isExpectingMoreDevices = false
            }

            oldDeviceList = displayableDevices
        }
    }

    private func showNewDeviceToast(deviceName: String) {
        guard FeatureFlags.biometricLinkedDeviceFlow else { return }
        presentToast(text: String(
            format: OWSLocalizedString(
                "DEVICE_LIST_UPDATE_NEW_DEVICE_TOAST",
                comment: "Message appearing on a toast indicating a new device was successfully linked. Embeds {{ device name }}"
            ),
            deviceName
        ))
    }

    // MARK: - View lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        refreshDevices()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        pollingRefreshTimer?.invalidate()
        pollingRefreshTimer = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if shouldShowFinishLinkingSheet {
            // Only show the sheet once even if viewDidAppear is
            // called multiple times while waiting for the link.
            self.shouldShowFinishLinkingSheet = false

            let sheet = HeroSheetViewController(
                heroImage: UIImage(named: "linked-devices")!,
                title: OWSLocalizedString(
                    "LINK_NEW_DEVICE_FINISH_ON_OTHER_DEVICE_SHEET_TITLE",
                    comment: "Title for a sheet when a user has started linking a device informing them to finish the process on that other device"
                ),
                body: OWSLocalizedString(
                    "LINK_NEW_DEVICE_FINISH_ON_OTHER_DEVICE_SHEET_BODY",
                    comment: "Body text for a sheet when a user has started linking a device informing them to finish the process on that other device"
                ),
                buttonTitle: CommonStrings.continueButton
            )
            self.finishLinkingSheet = sheet

            // Presenting it in viewDidAppear prevents the background dimming
            DispatchQueue.main.async {
                self.present(sheet, animated: true)
            }
        }
    }

    // MARK: - Events

    @objc
    private func refreshDevices() {
        AssertIsOnMainThread()

        _ = OWSDevicesService.refreshDevices()
    }

    @objc
    private func deviceListUpdateSucceeded() {
        AssertIsOnMainThread()

        refreshControl.endRefreshing()
    }

    @objc
    private func deviceListUpdateFailed(notification: Notification) {
        AssertIsOnMainThread()

        guard let error = notification.object as? Error else {
            owsFailDebug("Missing error.")
            return
        }
        if error.isNetworkFailureOrTimeout {
            return
        }

        showUpdateFailureAlert(error: error)
    }

    @objc
    private func deviceListUpdateModifiedDeviceList() {
        AssertIsOnMainThread()

        // Got our new device, we can stop refreshing.
        pollingRefreshTimer?.invalidate()
        pollingRefreshTimer = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.refreshControl.attributedTitle = nil
        }
    }

    // MARK: -

    private func showUpdateFailureAlert(error: Error) {
        AssertIsOnMainThread()

        let alertTitle = OWSLocalizedString("DEVICE_LIST_UPDATE_FAILED_TITLE",
                                           comment: "Alert title that can occur when viewing device manager.")
        let alert = ActionSheetController(title: alertTitle,
                                          message: error.userErrorDescription)
        alert.addAction(ActionSheetAction(title: CommonStrings.retryButton,
                                          style: .default) { _ in
                                            self.refreshDevices()
            })
        alert.addAction(OWSActionSheets.dismissAction)

        refreshControl.endRefreshing()
        presentActionSheet(alert)
    }

    private func showLinkNewDeviceView() {
        AssertIsOnMainThread()

        let linkView = LinkDeviceViewController()
        linkView.delegate = self
        navigationController?.pushViewController(linkView, animated: true)
    }

    @MainActor
    private func getCameraPermissionsThenShowLinkNewDeviceView() {
        self.ows_askForCameraPermissions { granted in
            guard granted else {
                return
            }
            self.showLinkNewDeviceView()
        }
    }

    private func didTapLinkDeviceButton() {
        let context = DeviceOwnerAuthenticationType.localAuthenticationContext()

        var error: NSError?
        let canEvaluatePolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        guard canEvaluatePolicy && error == nil else {
            let result = self.handleAuthenticationError(error as Error?)
            switch result {
            case .failed(let error):
                self.showError(error)
            case .canceled:
                break
            case .continueWithoutAuthentication:
                self.getCameraPermissionsThenShowLinkNewDeviceView()
            }
            return
        }

        let sheet = HeroSheetViewController(
            heroImage: UIImage(named: "phone-lock")!,
            title: OWSLocalizedString(
                "LINK_NEW_DEVICE_AUTHENTICATION_INFO_SHEET_TITLE",
                comment: "Title for a sheet when a user tries to link a device informing them that they will need to authenticate their device"
            ),
            body: OWSLocalizedString(
                "LINK_NEW_DEVICE_AUTHENTICATION_INFO_SHEET_BODY",
                comment: "Body text for a sheet when a user tries to link a device informing them that they will need to authenticate their device"
            ),
            buttonTitle: CommonStrings.continueButton
        ) { [weak self, context] in
            self?.dismiss(animated: true)
            Task {
                await self?.authenticateThenShowLinkNewDeviceView(context: context)
            }
        }

        self.present(sheet, animated: true)
    }

    private func authenticateThenShowLinkNewDeviceView(context: LAContext) async {
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: OWSLocalizedString(
                    "LINK_NEW_DEVICE_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock device linking."
                )
            )
            self.getCameraPermissionsThenShowLinkNewDeviceView()
        } catch {
            let result = self.handleAuthenticationError(error)
            switch result {
            case .failed(let error):
                self.showError(error)
            case .canceled:
                break
            case .continueWithoutAuthentication:
                self.getCameraPermissionsThenShowLinkNewDeviceView()
            }
        }
    }

    private enum AuthenticationErrorResult {
        case failed(OWSError)
        case canceled
        case continueWithoutAuthentication
    }

    private func showError(_ error: OWSError) {
        Logger.error(error.userErrorDescription)
        OWSActionSheets.showActionSheet(
            title: DeviceAuthenticationErrorMessage.errorSheetTitle,
            message: error.userErrorDescription,
            fromViewController: self
        )
    }

    private func handleAuthenticationError(_ error: Error?) -> AuthenticationErrorResult {
        let errorMessage: String
        switch (error as? LAError)?.code {
        case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet, .touchIDNotAvailable, .touchIDNotEnrolled:
            Logger.info("local authentication not enrolled")
            return .continueWithoutAuthentication
        case .userCancel, .userFallback, .systemCancel, .appCancel:
            Logger.info("local authentication cancelled.")
            return .canceled
        case .biometryLockout, .touchIDLockout:
            Logger.error("local authentication error: lockout.")
            errorMessage = DeviceAuthenticationErrorMessage.lockout
        case .authenticationFailed:
            Logger.error("local authentication error: authenticationFailed.")
            errorMessage = DeviceAuthenticationErrorMessage.authenticationFailed
        case .invalidContext:
            owsFailDebug("context not valid.")
            errorMessage = DeviceAuthenticationErrorMessage.unknownError
        case .notInteractive:
            // Example: app was backgrounded
            owsFailDebug("context not interactive.")
            errorMessage = DeviceAuthenticationErrorMessage.unknownError
        case .none:
            owsFailDebug("Unexpected error: \(String(describing: error))")
            errorMessage = DeviceAuthenticationErrorMessage.unknownError
        @unknown default:
            owsFailDebug("Unexpected enum value.")
            errorMessage = DeviceAuthenticationErrorMessage.unknownError
        }

        let owsError = OWSError(
            error: .localAuthenticationError,
            description: errorMessage,
            isRetryable: false
        )

        return .failed(owsError)
    }

    // MARK: -

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let addDeviceSection = OWSTableSection()
        addDeviceSection.footerTitle = OWSLocalizedString(
            "LINK_NEW_DEVICE_SUBTITLE",
            comment: "Subheading for 'Link New Device' navigation"
        )
        addDeviceSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "LINK_NEW_DEVICE_TITLE",
                comment: "Navigation title when scanning QR code to add new device."
            ),
            actionBlock: { [weak self] in
                if FeatureFlags.biometricLinkedDeviceFlow {
                    self?.didTapLinkDeviceButton()
                } else {
                    self?.getCameraPermissionsThenShowLinkNewDeviceView()
                }
            }
        ))
        contents.add(addDeviceSection)

        if !displayableDevices.isEmpty {
            let devicesSection = OWSTableSection()
            for displayableDevice in displayableDevices {
                let item = OWSTableItem(customCellBlock: { [weak self] in
                    let cell = DeviceTableViewCell()
                    OWSTableItem.configureCell(cell)
                    cell.isEditing = self?.isEditing ?? false
                    cell.configure(with: displayableDevice) {
                        self?.showUnlinkDeviceConfirmAlert(
                            displayableDevice: displayableDevice
                        )
                    }
                    return cell
                })
                devicesSection.add(item)
            }
            if shouldShowDeviceIdsBecauseUserIsInternal {
                devicesSection.footerTitle = "Device IDs (and this message) are only shown to internal users."
            }
            contents.add(devicesSection)
        }

        self.contents = contents
    }

    private func updateNavigationItems() {
        // Don't show edit button for an empty table
        if displayableDevices.isEmpty {
            navigationItem.rightBarButtonItem = nil
            didTapDoneEditing()
        } else {
            navigationItem.rightBarButtonItem = isEditing
                ? .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDoneEditing))
                : .init(barButtonSystemItem: .edit, target: self, action: #selector(didTapStartEditing))
        }
    }

    @objc
    private func didTapDoneEditing() {
        guard isEditing else { return }
        isEditing = false
        updateNavigationItems()
        defaultSeparatorInsetLeading = Self.cellHInnerMargin
        updateTableContents()
    }

    @objc
    private func didTapStartEditing() {
        guard !isEditing else { return }
        isEditing = true
        updateNavigationItems()
        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing
        updateTableContents()
    }

    private func showUnlinkDeviceConfirmAlert(displayableDevice: DisplayableDevice) {
        AssertIsOnMainThread()

        let titleFormat = OWSLocalizedString("UNLINK_CONFIRMATION_ALERT_TITLE",
                                                        comment: "Alert title for confirming device deletion")
        let title = String(format: titleFormat, displayableDevice.displayName)
        let message = OWSLocalizedString("UNLINK_CONFIRMATION_ALERT_BODY",
                                                    comment: "Alert message to confirm unlinking a device")
        let alert = ActionSheetController(title: title, message: message)
        alert.addAction(
            ActionSheetAction(
                title: OWSLocalizedString(
                    "UNLINK_ACTION",
                    comment: "button title for unlinking a device"
                ),
                accessibilityIdentifier: "confirm_unlink_device",
                style: .destructive,
                handler: { _ in
                    self.unlinkDevice(displayableDevice.device)
                }
            )
        )
        alert.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(alert)
    }

    private func unlinkDevice(_ device: OWSDevice) {
        OWSDevicesService.unlinkDevice(device,
                                       success: { [weak self] in
                                        Logger.info("Removing unlinked device with deviceId: \(device.deviceId)")
                                        SSKEnvironment.shared.databaseStorageRef.write { transaction in
                                            device.anyRemove(transaction: transaction)
                                        }
                                        DispatchQueue.main.async {
                                            self?.updateDeviceList()
                                        }
            },
                                       failure: { [weak self] (error) in
                                        DispatchQueue.main.async {
                                            self?.showUnlinkFailedAlert(device: device, error: error)
                                        }
        })
    }

    private func showUnlinkFailedAlert(device: OWSDevice, error: Error) {
        AssertIsOnMainThread()

        let title = OWSLocalizedString("UNLINKING_FAILED_ALERT_TITLE",
                                      comment: "Alert title when unlinking device fails")
        let alert = ActionSheetController(title: title, message: error.userErrorDescription)
        alert.addAction(ActionSheetAction(title: CommonStrings.retryButton,
                                          accessibilityIdentifier: "retry_unlink_device",
                                          style: .default) { [weak self] _ in
                                            self?.unlinkDevice(device)
            })
        alert.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(alert)
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }
}

// MARK: -

extension LinkedDevicesTableViewController: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdate(tableName: OWSDevice.databaseTableName) else {
            return
        }

        updateDeviceList()
    }

    func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        updateDeviceList()
    }

    func databaseChangesDidReset() {
        AssertIsOnMainThread()

        updateDeviceList()
    }
}

// MARK: -

extension LinkedDevicesTableViewController: LinkDeviceViewControllerDelegate {

    func expectMoreDevices() {

        isExpectingMoreDevices = true

        // When you delete and re-add a device, you will be returned to this view in editing mode, making your newly
        // added device appear with a delete icon. Probably not what you want.
        self.isEditing = false

        pollingRefreshTimer?.invalidate()
        pollingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.refreshDevices()
        }

        let progressText = OWSLocalizedString("WAITING_TO_COMPLETE_DEVICE_LINK_TEXT",
                                             comment: "Activity indicator title, shown upon returning to the device manager, until you complete the provisioning process on desktop")
        let progressTitle = progressText.asAttributedString

        // HACK to get refreshControl title to align properly.
        refreshControl.attributedTitle = progressTitle
        refreshControl.endRefreshing()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.refreshControl.attributedTitle = progressTitle
            self.refreshControl.beginRefreshing()
            // Needed to show refresh control programmatically
            self.tableView.setContentOffset(CGPoint(x: 0, y: -self.refreshControl.height),
                                            animated: false)
        }
        // END HACK to get refreshControl title to align properly.
    }
}

// MARK: -

private class DeviceTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var unlinkAction: (() -> Void)?
    private let nameLabel = UILabel()
    private let linkedLabel = UILabel()
    private let lastSeenLabel = UILabel()
    private lazy var unlinkButton: UIButton = {
        let button = UIButton()
        button.imageView?.contentMode = .scaleAspectFit
        button.setImage(UIImage(imageLiteralResourceName: "minus-circle-fill"), for: .normal)
        button.addTarget(self, action: #selector(didTapUnlink(sender:)), for: .touchUpInside)
        button.tintColor = .ows_accentRed
        button.isHidden = true
        button.autoSetDimension(.width, toSize: 24)
        return button
    }()

    private func configure() {
        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        let verticalStack = UIStackView(arrangedSubviews: [ nameLabel, linkedLabel, lastSeenLabel ])
        verticalStack.axis = .vertical
        verticalStack.alignment = .leading
        verticalStack.spacing = 2

        let horizontalStack = UIStackView(arrangedSubviews: [ unlinkButton, verticalStack ])
        horizontalStack.axis = .horizontal
        horizontalStack.spacing = 16
        contentView.addSubview(horizontalStack)
        horizontalStack.autoPinEdgesToSuperviewMargins()
    }

    @objc
    private func didTapUnlink(sender: UIButton) {
        unlinkAction?()
    }

    func configure(
        with displayableDevice: DisplayableDevice,
        unlinkAction: @escaping () -> Void
    ) {
        // TODO: This is not super, but the best we can do until
        // OWSTableViewController2 supports delete actions for
        // the inset cell style (which probably means building
        // custom editing support)
        self.unlinkAction = unlinkAction
        unlinkButton.isHidden = !isEditing

        configureLabelColors()
        nameLabel.font = OWSTableItem.primaryLabelFont
        linkedLabel.font = .dynamicTypeFootnote
        lastSeenLabel.font = .dynamicTypeFootnote

        if shouldShowDeviceIdsBecauseUserIsInternal {
            nameLabel.text = LocalizationNotNeeded(String(
                format: "#%ld: %@",
                displayableDevice.device.deviceId,
                displayableDevice.displayName
            ))
        } else {
            nameLabel.text = displayableDevice.displayName
        }

        let linkedFormatString = OWSLocalizedString("DEVICE_LINKED_AT_LABEL", comment: "{{Short Date}} when device was linked.")
        linkedLabel.text = String(
            format: linkedFormatString,
            DateUtil.dateFormatter.string(
                from: displayableDevice.device.createdAt
            )
        )

        // lastSeenAt is stored at day granularity. At midnight UTC.
        // Making it likely that when you first link a device it will
        // be "last seen" the day before it was created, which looks broken.
        let displayedLastSeenAt = max(
            displayableDevice.device.createdAt,
            displayableDevice.device.lastSeenAt
        )
        let lastSeenFormatString = OWSLocalizedString(
            "DEVICE_LAST_ACTIVE_AT_LABEL",
            comment: "{{Short Date}} when device last communicated with Signal Server."
        )
        lastSeenLabel.text = String(format: lastSeenFormatString, DateUtil.dateFormatter.string(from: displayedLastSeenAt))
    }

    private func configureLabelColors() {
        nameLabel.textColor = Theme.primaryTextColor
        linkedLabel.textColor = Theme.secondaryTextAndIconColor
        lastSeenLabel.textColor = Theme.secondaryTextAndIconColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        OWSTableItem.configureCell(self)
        configureLabelColors()
    }
}
