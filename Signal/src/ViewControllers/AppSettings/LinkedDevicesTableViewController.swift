//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class LinkedDevicesTableViewController: OWSTableViewController {

    private var devices = [OWSDevice]()

    private var pollingRefreshTimer: Timer?

    private var isExpectingMoreDevices = false

    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LINKED_DEVICES_TITLE", comment: "Menu item and navbar title for the device manager")

        self.useThemeBackgroundColors = true

        refreshControl.addTarget(self, action: #selector(refreshDevices), for: .valueChanged)

        tableView.refreshControl = refreshControl

        updateTableContents()

        addObservers()

        updateDeviceList()
    }

    private func addObservers() {
        Self.databaseStorage.appendUIDatabaseSnapshotDelegate(self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceListUpdateSucceeded),
                                               name: .deviceListUpdateSucceeded,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceListUpdateFailed),
                                               name: .deviceListUpdateFailed,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceListUpdateModifiedDeviceList),
                                               name: .deviceListUpdateModifiedDeviceList,
                                               object: nil)
    }

    // TODO: Could we DRY this up in OWSTableViewController when
    // useThemeBackgroundColors = true?
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        view.backgroundColor = Theme.backgroundColor
        tableView.backgroundColor = Theme.backgroundColor
        tableView.separatorColor = Theme.cellSeparatorColor

        updateTableContents()
    }

    // MARK: -

    private func updateDeviceList() {
        AssertIsOnMainThread()

        var devices = Self.databaseStorage.read { transaction in
            OWSDevice.anyFetchAll(transaction: transaction).filter {
                !$0.isPrimaryDevice()
            }
        }
        devices.sort { (left, right) -> Bool in
            left.createdAt.compare(right.createdAt) == .orderedAscending
        }
        self.devices = devices
        if devices.isEmpty {
            self.isEditing = false
        }

        // Don't show edit button for an empty table
        if devices.isEmpty {
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.rightBarButtonItem = editButtonItem
        }

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
                                          message: error.localizedDescription)
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

        if !devices.isEmpty {
            let devicesSection = OWSTableSection()
            for device in devices {
                let item = OWSTableItem(customCellBlock: {
                    let cell = OWSDeviceTableViewCell()
                    OWSTableItem.configureCell(cell)
                    cell.configure(with: device)
                    return cell
                })
                let deleteTitle = NSLocalizedString("UNLINK_ACTION",
                                                    comment: "button title for unlinking a device")
                item.deleteAction = OWSTableItemEditAction(title: deleteTitle) { [weak self] in
                    self?.showUnlinkDeviceConfirmAlert(device: device)
                }
                devicesSection.add(item)
            }
            contents.addSection(devicesSection)
        }

        let addDeviceSection = OWSTableSection()
        addDeviceSection.add(OWSTableItem(customCellBlock: { () -> UITableViewCell in
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "AddNewDevice")
            OWSTableItem.configureCell(cell)
            cell.textLabel?.text = NSLocalizedString("LINK_NEW_DEVICE_TITLE",
                                                    comment: "Navigation title when scanning QR code to add new device.")
            cell.detailTextLabel?.text = NSLocalizedString("LINK_NEW_DEVICE_SUBTITLE",
                                                          comment: "Subheading for 'Link New Device' navigation")
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "add_new_linked_device"
            return cell
        }) { [weak self] in
                self?.getCameraPermissionsThenShowLinkNewDeviceView()

            })
        contents.addSection(addDeviceSection)

        self.contents = contents
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
        let alert = ActionSheetController(title: title, message: error.localizedDescription)
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

extension LinkedDevicesTableViewController: UIDatabaseSnapshotDelegate {

    func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
    }

    func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard databaseChanges.didUpdateModel(collection: OWSDevice.collection()) else {
            return
        }

        updateDeviceList()
    }

    func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        updateDeviceList()
    }

    func uiDatabaseSnapshotDidReset() {
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
            // Needed to show refresh control programatically
            self.tableView.setContentOffset(CGPoint(x: 0, y: -self.refreshControl.height),
                                            animated: false)
        }
        // END HACK to get refreshControl title to align properly.
    }
}
