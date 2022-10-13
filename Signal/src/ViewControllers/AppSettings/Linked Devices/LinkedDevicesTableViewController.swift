//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class LinkedDevicesTableViewController: OWSTableViewController2 {

    private var devices = [OWSDevice]()

    private var pollingRefreshTimer: Timer?

    private var isExpectingMoreDevices = false

    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LINKED_DEVICES_TITLE", comment: "Menu item and navbar title for the device manager")

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

        var devices = Self.databaseStorage.read { transaction in
            OWSDevice.anyFetchAll(transaction: transaction).filter {
                !$0.isPrimaryDevice()
            }
        }

        if DebugFlags.fakeLinkedDevices {
            devices.append(.init(uniqueId: "test", createdAt: .distantPast, deviceId: 10, lastSeenAt: Date(), name: "Fake Device"))
            devices.append(.init(uniqueId: "test2", createdAt: .distantPast, deviceId: 4, lastSeenAt: Date(), name: "Fake Device 2"))
        }

        devices.sort { $0.createdAt < $1.createdAt }
        self.devices = devices
        if devices.isEmpty {
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
    func refreshDevices() {
        AssertIsOnMainThread()

        OWSDevicesService.refreshDevices()
    }

    @objc
    func deviceListUpdateSucceeded() {
        AssertIsOnMainThread()

        refreshControl.endRefreshing()
    }

    @objc
    func deviceListUpdateFailed(notification: Notification) {
        AssertIsOnMainThread()

        guard let error = notification.object as? Error else {
            owsFailDebug("Missing error.")
            return
        }
        if error.isNetworkConnectivityFailure {
            return
        }

        showUpdateFailureAlert(error: error)
    }

    @objc
    func deviceListUpdateModifiedDeviceList() {
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

        let alertTitle = NSLocalizedString("DEVICE_LIST_UPDATE_FAILED_TITLE",
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

        let linkView = OWSLinkDeviceViewController()
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
        addDeviceSection.footerTitle = NSLocalizedString(
            "LINK_NEW_DEVICE_SUBTITLE",
            comment: "Subheading for 'Link New Device' navigation"
        )
        addDeviceSection.add(.disclosureItem(
            withText: NSLocalizedString(
                "LINK_NEW_DEVICE_TITLE",
                comment: "Navigation title when scanning QR code to add new device."
            ),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "add_new_linked_device"),
            actionBlock: { [weak self] in
                self?.getCameraPermissionsThenShowLinkNewDeviceView()
            }
        ))
        contents.addSection(addDeviceSection)

        if !devices.isEmpty {
            let devicesSection = OWSTableSection()
            for device in devices {
                let item = OWSTableItem(customCellBlock: { [weak self] in
                    let cell = OWSDeviceTableViewCell()
                    OWSTableItem.configureCell(cell)
                    cell.isEditing = self?.isEditing ?? false
                    cell.configure(with: device) {
                        self?.showUnlinkDeviceConfirmAlert(device: device)
                    }
                    return cell
                })
                devicesSection.add(item)
            }
            contents.addSection(devicesSection)
        }

        self.contents = contents
    }

    private func updateNavigationItems() {
        // Don't show edit button for an empty table
        if devices.isEmpty {
            navigationItem.rightBarButtonItem = nil
            didTapDoneEditing()
        } else {
            navigationItem.rightBarButtonItem = isEditing
                ? .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDoneEditing))
                : .init(barButtonSystemItem: .edit, target: self, action: #selector(didTapStartEditing))
        }
    }

    @objc
    func didTapDoneEditing() {
        guard isEditing else { return }
        isEditing = false
        updateNavigationItems()
        defaultSeparatorInsetLeading = Self.cellHInnerMargin
        updateTableContents()
    }

    @objc
    func didTapStartEditing() {
        guard !isEditing else { return }
        isEditing = true
        updateNavigationItems()
        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing
        updateTableContents()
    }

    private func showUnlinkDeviceConfirmAlert(device: OWSDevice) {
        AssertIsOnMainThread()

        let titleFormat = NSLocalizedString("UNLINK_CONFIRMATION_ALERT_TITLE",
                                                        comment: "Alert title for confirming device deletion")
        let title = String(format: titleFormat, device.displayName())
        let message = NSLocalizedString("UNLINK_CONFIRMATION_ALERT_BODY",
                                                    comment: "Alert message to confirm unlinking a device")
        let alert = ActionSheetController(title: title, message: message)

        alert.addAction(ActionSheetAction(title: NSLocalizedString("UNLINK_ACTION",
                                                                   comment: "button title for unlinking a device"),
                                          accessibilityIdentifier: "confirm_unlink_device",
                                          style: .destructive) { _ in
                                            self.unlinkDevice(device)
            })
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

        let title = NSLocalizedString("UNLINKING_FAILED_ALERT_TITLE",
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

@objc
extension LinkedDevicesTableViewController: OWSLinkDeviceViewControllerDelegate {

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

        let progressText = NSLocalizedString("WAITING_TO_COMPLETE_DEVICE_LINK_TEXT",
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
