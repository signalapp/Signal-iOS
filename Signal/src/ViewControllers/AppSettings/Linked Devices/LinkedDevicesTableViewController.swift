//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

private struct DisplayableDevice {
    let device: OWSDevice
    let displayName: String
}

class LinkedDevicesTableViewController: OWSTableViewController2 {

    private var displayableDevices: [DisplayableDevice] = []

    private var pollingRefreshTimer: Timer?

    private var isExpectingMoreDevices = false

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
        Self.databaseStorage.appendDatabaseChangeDelegate(self)

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

        displayableDevices = databaseStorage.read { transaction -> [DisplayableDevice] in
            let justDevices = OWSDevice.anyFetchAll(transaction: transaction).filter {
                !$0.isPrimaryDevice
            }

            return justDevices.map { device -> DisplayableDevice in
                return .init(
                    device: device,
                    displayName: device.displayName(
                        identityManager: identityManager,
                        transaction: transaction
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

    // MARK: - Events

    @objc
    private func refreshDevices() {
        AssertIsOnMainThread()

        OWSDevicesService.refreshDevices()
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
        isExpectingMoreDevices = false

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

    private func getCameraPermissionsThenShowLinkNewDeviceView() {
        self.ows_askForCameraPermissions { granted in
            guard granted else {
                return
            }
            self.showLinkNewDeviceView()
        }
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
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "add_new_linked_device"),
            actionBlock: { [weak self] in
                self?.getCameraPermissionsThenShowLinkNewDeviceView()
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
                                        Self.databaseStorage.write { transaction in
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
}

// MARK: -

extension LinkedDevicesTableViewController: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard databaseChanges.didUpdateModel(collection: OWSDevice.collection()) else {
            return
        }

        updateDeviceList()
    }

    func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        updateDeviceList()
    }

    func databaseChangesDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

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
        pollingRefreshTimer = Timer.weakScheduledTimer(withTimeInterval: 10.0,
                                                       target: self,
                                                       selector: #selector(refreshDevices),
                                                       userInfo: nil,
                                                       repeats: true)

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

        if DebugFlags.internalSettings {
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
