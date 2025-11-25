//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SwiftUI
import SignalUI
import SignalServiceKit
import LocalAuthentication

// This has a long and awful name so that if the condition is ever changed,
// the text shown to internal users about it can be changed too.
private var shouldShowDeviceIdsBecauseUserIsInternal: Bool { DebugFlags.internalSettings }

// MARK: - LinkedDevicesViewModel

@MainActor
class LinkedDevicesViewModel: ObservableObject {

    @Published fileprivate var editMode: EditMode = .inactive
    @Published fileprivate var displayableDevices: [DisplayableDevice] = []
    @Published fileprivate var isLoading: Bool = false

    fileprivate enum Presentation {
        case newDeviceToast(deviceName: String, didSync: Bool)
        case linkDeviceAuthentication
        case renameDevice(displayableDevice: DisplayableDevice)
        case unlinkDeviceConfirmation(displayableDevice: DisplayableDevice)
        case updateFailureAlert(Error)
        case unlinkFailureAlert(device: OWSDevice, error: Error)
        case activityIndicator(UIViewController)
        case linkedDeviceEducation
        case linkAndSyncFailureAlert(PrimaryLinkNSyncError)
    }

    fileprivate var present = PassthroughSubject<Presentation, Never>()

    private enum NewDeviceExpectation {
        case link
        case linkAndSync
    }

    private var subscriptions = Set<AnyCancellable>()
    private var pollingRefreshTimer: Timer?
    private var oldDeviceList: [DisplayableDevice] = []
    private var newDeviceExpectation: NewDeviceExpectation? {
        didSet {
            shouldShowFinishLinkingSheet = newDeviceExpectation != nil
        }
    }
    private var deviceIdToIgnore: DeviceId?
    fileprivate var shouldShowFinishLinkingSheet = false

    private let backupArchiveErrorPresenter: BackupArchiveErrorPresenter
    private let databaseChangeObserver: DatabaseChangeObserver
    private let db: any DB
    private let deviceService: OWSDeviceService
    private let deviceStore: OWSDeviceStore
    private let identityManager: OWSIdentityManager

#if DEBUG
    private let isPreview: Bool
#endif

    init(isPreview: Bool = false) {
#if DEBUG
        self.isPreview = isPreview
#endif
        backupArchiveErrorPresenter = DependenciesBridge.shared.backupArchiveErrorPresenter
        databaseChangeObserver = DependenciesBridge.shared.databaseChangeObserver
        db = DependenciesBridge.shared.db
        deviceService = DependenciesBridge.shared.deviceService
        deviceStore = DependenciesBridge.shared.deviceStore
        identityManager = DependenciesBridge.shared.identityManager

        databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    func refreshDevices() async {
        if displayableDevices.isEmpty {
            self.isLoading = true
        }

#if DEBUG
        if isPreview {
            try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
            withAnimation {
                self.displayableDevices = [
                    .init(device: .previewItem(id: DeviceId(validating: 1)!, name: "iPad")),
                    .init(device: .previewItem(id: DeviceId(validating: 2)!, name: "macOS")),
                ]
            }
            self.isLoading = false
            return
        }
#endif

        do {
            let didAddOrRemove = try await deviceService.refreshDevices()

            if didAddOrRemove {
                pollingRefreshTimer?.invalidate()
                pollingRefreshTimer = nil
            }
        } catch let error where error.isNetworkFailureOrTimeout {
            // Ignore
        } catch let error {
            present.send(.updateFailureAlert(error))
        }

        if newDeviceExpectation == nil {
            self.isLoading = false
        }
    }

    private func updateDeviceList() {
        var displayableDevices = db.read { transaction -> [DisplayableDevice] in
            return deviceStore.fetchAll(tx: transaction)
                .filter { $0.isLinkedDevice }
                .map { DisplayableDevice(device: $0) }
        }

        if let deviceIdToIgnore {
            displayableDevices.removeAll { device in
                let shouldRemove = device.id == Int(deviceIdToIgnore.rawValue)
                if shouldRemove {
                    Logger.debug("Ignoring device \(device.id)")
                }
                return shouldRemove
            }
        }

        displayableDevices.sort { (lhs, rhs) in
            lhs.device.createdAt < rhs.device.createdAt
        }

        if oldDeviceList != displayableDevices {
            if
                let newDeviceExpectation,
                let newDevice = displayableDevices.last,
                newDevice != oldDeviceList.last
            {
                present.send(.newDeviceToast(
                    deviceName: newDevice.displayName,
                    didSync: newDeviceExpectation == .linkAndSync
                ))
                self.newDeviceExpectation = nil
                withAnimation {
                    self.isLoading = false
                }
            }

            oldDeviceList = displayableDevices
        }

        withAnimation {
            self.displayableDevices = displayableDevices

            if displayableDevices.isEmpty {
                self.editMode = .inactive
            }
        }

        self.clearDeliveredNewLinkedDevicesNotificationsAndMegaphone()
    }

    func unlinkDevice(_ device: OWSDevice) {
#if DEBUG
        guard !isPreview else {
            withAnimation {
                displayableDevices.removeAll { $0.device.deviceId == device.deviceId }
            }
            return
        }
#endif
        Task { [deviceService] in
            do {
                try await deviceService.unlinkDevice(device)
            } catch let error {
                return await MainActor.run {
                    present.send(.unlinkFailureAlert(device: device, error: error))
                }
            }

            Logger.info("Removing unlinked device with deviceId: \(device.deviceId)")

            await db.awaitableWrite { tx in
                deviceStore.remove(device, tx: tx)
            }

            await MainActor.run {
                updateDeviceList()
            }
        }
    }

    func renameDevice(
        _ displayableDevice: DisplayableDevice,
        to newName: String
    ) async throws {
        try await deviceService.renameDevice(
            device: displayableDevice.device,
            newName: newName,
        )
    }

    // MARK: DisplayableDevice

    struct DisplayableDevice: Hashable, Identifiable {
        let device: OWSDevice

        var id: Int { device.deviceId }
        var displayName: String { device.displayName }
        var createdAt: Date { device.createdAt }

        static func == (lhs: DisplayableDevice, rhs: DisplayableDevice) -> Bool {
            lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.createdAt == rhs.createdAt
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(displayName)
            hasher.combine(createdAt)
        }
    }
}

// MARK: DatabaseChangeDelegate

extension LinkedDevicesViewModel: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.didUpdate(tableName: OWSDevice.databaseTableName) else {
            return
        }

        updateDeviceList()
    }

    func databaseChangesDidUpdateExternally() {
        updateDeviceList()
    }

    func databaseChangesDidReset() {
        updateDeviceList()
    }
}

// MARK: LinkDeviceViewControllerDelegate

extension LinkedDevicesViewModel: LinkDeviceViewControllerDelegate {
    func didFinishLinking(
        _ linkNSyncData: LinkNSyncData?,
        from linkDeviceViewController: LinkDeviceViewController
    ) {
        self.deviceIdToIgnore = nil
        self.scheduleNewLinkedDeviceNotification()

        guard let linkNSyncData else {
            linkDeviceViewController.popToLinkedDeviceList { [weak self] in
                self?.expectMoreDevices()
            }
            return
        }

        // Don't wait for the view pop to start the linking process
        let linkAndSyncProgressModal = BackupProgressModal(style: .linkAndSync)
        linkDeviceViewController.popToLinkedDeviceList { [weak self] in
            self?.present.send(.activityIndicator(linkAndSyncProgressModal))
        }

        let linkNSyncTask = Task { @MainActor in
            let progress = await OWSSequentialProgress<PrimaryLinkNSyncProgressPhase>.createSink { progress in
                await MainActor.run {
                    linkAndSyncProgressModal.viewModel.updatePrimaryLinkingProgress(progress: progress)
                }
            }
            do {
                try await DependenciesBridge.shared.linkAndSyncManager.waitForLinkingAndUploadBackup(
                    ephemeralBackupKey: linkNSyncData.ephemeralBackupKey,
                    tokenId: linkNSyncData.tokenId,
                    progress: progress
                )
                Task { @MainActor in
                    await linkAndSyncProgressModal.completeAndDismiss()
                }
            } catch {
                linkAndSyncProgressModal.dismiss(animated: true) {
                    guard let error = error as? PrimaryLinkNSyncError else {
                        owsFailDebug("Unexpected error!")
                        return
                    }
                    switch error {
                    case let .cancelled(linkedDeviceId):
                        // Don't show anything
                        self.deviceIdToIgnore = linkedDeviceId
                        return
                    case
                            .errorWaitingForLinkedDevice,
                            .errorUploadingBackup,
                            .errorMarkingBackupUploaded,
                            .errorGeneratingBackup:
                        self.present.send(.linkAndSyncFailureAlert(error))
                    }
                }
                self.expectMoreDevices()
                return
            }
            self.newDeviceExpectation = .linkAndSync
            await self.refreshDevices()
        }
        linkAndSyncProgressModal.backupTask = linkNSyncTask
    }

    fileprivate func expectMoreDevices() {
        newDeviceExpectation = .link
        editMode = .inactive

        pollingRefreshTimer?.invalidate()
        pollingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.newDeviceExpectation != nil else {
                    timer.invalidate()
                    return
                }

                Task {
                    await self.refreshDevices()
                }
            }
        }
    }

    private func scheduleNewLinkedDeviceNotification() {
        let deviceLinkTimestamp = Date()
        let notificationDelay = TimeInterval.random(in: .hour...(.hour * 3))
        db.write { tx in
            deviceStore.setMostRecentlyLinkedDeviceDetails(
                linkedTime: deviceLinkTimestamp,
                notificationDelay: notificationDelay,
                tx: tx
            )
        }
        SSKEnvironment.shared.notificationPresenterRef.scheduleNotifyForNewLinkedDevice(deviceLinkTimestamp: deviceLinkTimestamp)
    }

    private func clearDeliveredNewLinkedDevicesNotificationsAndMegaphone() {
        let details = db.read { tx in
            deviceStore.mostRecentlyLinkedDeviceDetails(tx: tx)
        }

        // Only clear them if the delivery time for the notification and
        // megaphone has passed, otherwise it would just clear right away
        // after linking.
        if let details, Date() > details.shouldRemindUserAfter {
            db.write { tx in
                deviceStore.clearMostRecentlyLinkedDeviceDetails(tx: tx)
                ExperienceUpgradeManager.clearExperienceUpgrade(
                    .newLinkedDeviceNotification,
                    transaction: tx
                )
            }
        }

        SSKEnvironment.shared.notificationPresenterRef.clearDeliveredNewLinkedDevicesNotifications()
    }
}

// MARK: - LinkedDevicesHostingController

class LinkedDevicesHostingController: HostingContainer<LinkedDevicesView> {
    private let viewModel: LinkedDevicesViewModel

    private var subscriptions = Set<AnyCancellable>()

    private weak var finishLinkingSheet: HeroSheetViewController?

    init(isPreview: Bool = false) {
        self.viewModel = LinkedDevicesViewModel(isPreview: isPreview)

        super.init(wrappedView: LinkedDevicesView(viewModel: viewModel))

        OWSTableViewController2.removeBackButtonText(viewController: self)

        viewModel.present.sink { [weak self] presentation in
            guard let self else { return }
            switch presentation {
            case let .newDeviceToast(deviceName, didSync):
                if let finishLinkingSheet {
                    finishLinkingSheet.dismiss(animated: true) {
                        self.showNewDeviceToast(deviceName: deviceName, didSync: didSync)
                    }
                } else {
                    self.showNewDeviceToast(deviceName: deviceName, didSync: didSync)
                }
            case let .updateFailureAlert(error):
                self.showUpdateFailureAlert(error: error)
            case .linkDeviceAuthentication:
                self.didTapLinkDeviceButton()
            case let .renameDevice(displayableDevice):
                self.showRenameDeviceView(device: displayableDevice)
            case let .unlinkDeviceConfirmation(displayableDevice):
                self.showUnlinkDeviceConfirmAlert(displayableDevice: displayableDevice)
            case let .unlinkFailureAlert(device, error):
                self.showUnlinkFailedAlert(device: device, error: error)
            case let .activityIndicator(modal):
                self.present(modal, animated: true)
            case .linkedDeviceEducation:
                self.present(LinkedDevicesEducationSheet(), animated: true)
            case let .linkAndSyncFailureAlert(error):
                switch error {
                case .errorMarkingBackupUploaded(let retryHandler), .errorUploadingBackup(let retryHandler):
                    self.showLinkAndSyncRetryableFailureAlert(errorRetryHandler: retryHandler)
                case .errorWaitingForLinkedDevice:
                    self.showLinkAndSyncUnretryableFailureAlert(contactSupportEmailFilter: nil)
                case .errorGeneratingBackup:
                    self.showLinkAndSyncUnretryableFailureAlert(contactSupportEmailFilter: .backupExportFailed)
                case .cancelled:
                    break
                }
            }
        }.store(in: &subscriptions)

        viewModel.$editMode
            .sink { [weak self] editMode in
                self?.updateNavigationItems(editMode: editMode)
            }
            .store(in: &subscriptions)

        self.title = OWSLocalizedString(
            "LINKED_DEVICES_TITLE",
            comment: "Menu item and navbar title for the device manager"
        )
    }

    private func updateNavigationItems(editMode: EditMode? = nil) {
        // @Published sends the new value before the view model
        // itself updates, so its value needs to be passed in.
        let editMode = editMode ?? viewModel.editMode

        navigationItem.rightBarButtonItem = .systemItem(
            editMode.isEditing ? .done : .edit
        ) { [weak viewModel] in
            withAnimation {
                viewModel?.editMode = editMode.isEditing ? .inactive : .active
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if viewModel.shouldShowFinishLinkingSheet {
            // Only show the sheet once even if viewDidAppear is
            // called multiple times while waiting for the link.
            viewModel.shouldShowFinishLinkingSheet = false

            let sheet = HeroSheetViewController(
                hero: .image(UIImage(named: "linked-devices")!),
                title: OWSLocalizedString(
                    "LINK_NEW_DEVICE_FINISH_ON_OTHER_DEVICE_SHEET_TITLE",
                    comment: "Title for a sheet when a user has started linking a device informing them to finish the process on that other device"
                ),
                body: OWSLocalizedString(
                    "LINK_NEW_DEVICE_FINISH_ON_OTHER_DEVICE_SHEET_BODY",
                    comment: "Body text for a sheet when a user has started linking a device informing them to finish the process on that other device"
                ),
                primaryButton: .dismissing(title: CommonStrings.continueButton)
            )
            self.finishLinkingSheet = sheet

            // Presenting it in viewDidAppear prevents the background dimming
            DispatchQueue.main.async {
                self.present(sheet, animated: true)
            }
        }
    }

    // MARK: Device linking

    private func showNewDeviceToast(deviceName: String, didSync: Bool) {
        let title: String = if didSync {
            OWSLocalizedString(
                "DEVICE_LIST_UPDATE_NEW_DEVICE_SYNCED_TOAST",
                comment: "Message appearing on a toast indicating a new device was successfully linked and synced."
            )
        } else {
            OWSLocalizedString(
                "DEVICE_LIST_UPDATE_NEW_DEVICE_TOAST",
                comment: "Message appearing on a toast indicating a new device was successfully linked. Embeds {{ device name }}"
            )
        }

        presentToast(text: String(format: title, deviceName))
    }

    private func showUpdateFailureAlert(error: Error) {
        AssertIsOnMainThread()

        let alertTitle = OWSLocalizedString(
            "DEVICE_LIST_UPDATE_FAILED_TITLE",
            comment: "Alert title that can occur when viewing device manager."
        )
        let alert = ActionSheetController(title: alertTitle,
                                          message: error.userErrorDescription)
        alert.addAction(ActionSheetAction(
            title: CommonStrings.retryButton,
            style: .default) { [weak self] _ in
                Task {
                    await self?.viewModel.refreshDevices()
                }
            }
        )
        alert.addAction(OWSActionSheets.dismissAction)

        presentActionSheet(alert)
    }

    private func showLinkNewDeviceView(skipEducationSheet: Bool = false) {
        AssertIsOnMainThread()

        func presentLinkView(_ linkView: LinkDeviceViewController) {
            linkView.delegate = viewModel
            navigationController?.pushViewController(linkView, animated: true)
        }

        self.ows_askForCameraPermissions { granted in
            guard granted else {
                return
            }

            presentLinkView(LinkDeviceViewController(
                skipEducationSheet: skipEducationSheet
            ))
        }
    }

    private func didTapLinkDeviceButton() {
        let localDeviceAuth = LocalDeviceAuthentication()
        let localDeviceAuthAttemptToken: LocalDeviceAuthentication.AttemptToken

        switch localDeviceAuth.checkCanAttempt() {
        case .success(let attemptToken):
            localDeviceAuthAttemptToken = attemptToken
        case .failure(.notRequired):
            showLinkNewDeviceView()
            return
        case .failure(.canceled):
            return
        case .failure(.genericError(let localizedErrorMessage)):
            showError(message: localizedErrorMessage)
            return
        }

        let sheet = HeroSheetViewController(
            hero: .image(UIImage(named: "phone-lock")!),
            title: OWSLocalizedString(
                "LINK_NEW_DEVICE_AUTHENTICATION_INFO_SHEET_TITLE",
                comment: "Title for a sheet when a user tries to link a device informing them that they will need to authenticate their device"
            ),
            body: OWSLocalizedString(
                "LINK_NEW_DEVICE_AUTHENTICATION_INFO_SHEET_BODY",
                comment: "Body text for a sheet when a user tries to link a device informing them that they will need to authenticate their device"
            ),
            primaryButton: .init(
                title: CommonStrings.continueButton
            ) { [weak self] _ in
                self?.dismiss(animated: true)
                Task {
                    await self?.authenticateThenShowLinkNewDeviceView(
                        localDeviceAuth: localDeviceAuth,
                        localDeviceAuthAttemptToken: localDeviceAuthAttemptToken,
                    )
                }
            }
        )

        self.present(sheet, animated: true)
    }

    private func showLinkAndSyncRetryableFailureAlert(errorRetryHandler: PrimaryLinkNSyncError.RetryHandler) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_FAILED_TITLE",
                comment: "Title for a sheet indicating that a newly linked device failed to sync messages."
            ),
            message: OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_FAILED_RETRYABLE_MESSAGE",
                comment: "Message for a sheet indicating that a newly linked device failed to sync messages with a retryable error."
            )
        )
        actionSheet.addAction(
            .init(
                title: CommonStrings.retryButton,
                style: .cancel
            ) { [weak self] _ in
                Task {
                    await errorRetryHandler.tryToResetLinkedDevice()
                    await MainActor.run {
                        self?.showLinkNewDeviceView(skipEducationSheet: true)
                    }
                }
            }
        )
        actionSheet.addAction(
            .init(
                title: OWSLocalizedString(
                    "LINK_NEW_DEVICE_SYNC_FAILED_CONTINUE_BUTTON",
                    comment: "Button for a sheet indicating that a newly linked device failed to sync messages, to link without transferring."
                )
            ) { _ in
                Task {
                    await errorRetryHandler.tryToContinueWithoutSyncing()
                }
            }
        )
        actionSheet.onDismiss = { [weak self] in
            self?.viewModel.expectMoreDevices()
        }
        presentActionSheet(actionSheet)
    }

    private func showLinkAndSyncUnretryableFailureAlert(
        contactSupportEmailFilter: ContactSupportActionSheet.EmailFilter?
    ) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_FAILED_TITLE",
                comment: "Title for a sheet indicating that a newly linked device failed to sync messages."
            ),
            message: OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_FAILED_MESSAGE",
                comment: "Message for a sheet indicating that a newly linked device failed to sync messages."
            )
        )
        if let contactSupportEmailFilter {
            actionSheet.addAction(ActionSheetAction(title: CommonStrings.contactSupport) { [weak self] _ in
                guard let self else { return }

                ContactSupportActionSheet.present(
                    emailFilter: contactSupportEmailFilter,
                    logDumper: .fromGlobals(),
                    fromViewController: self
                )
            })
        }
        actionSheet.addAction(.init(title: CommonStrings.learnMore) { _ in
            CurrentAppContext().open(URL.Support.linkedDevices, completion: nil)
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.continueButton, style: .cancel))

        actionSheet.onDismiss = { [weak self] in
            self?.viewModel.expectMoreDevices()
            DependenciesBridge.shared.backupArchiveErrorPresenter.presentOverTopmostViewController(completion: {})
        }
        presentActionSheet(actionSheet)
    }

    // MARK: Authentication

    private func authenticateThenShowLinkNewDeviceView(
        localDeviceAuth: LocalDeviceAuthentication,
        localDeviceAuthAttemptToken: LocalDeviceAuthentication.AttemptToken,
    ) async {
        switch await localDeviceAuth.attempt(token: localDeviceAuthAttemptToken) {
        case .success, .failure(.notRequired):
            showLinkNewDeviceView()
        case .failure(.canceled):
            break
        case .failure(.genericError(let localizedErrorMessage)):
            showError(message: localizedErrorMessage)
        }
    }

    private func showError(message: String) {
        Logger.error(message)
        OWSActionSheets.showActionSheet(
            title: DeviceAuthenticationErrorMessage.errorSheetTitle,
            message: message,
            fromViewController: self
        )
    }

    // MARK: Renaming

    private func showRenameDeviceView(device: LinkedDevicesViewModel.DisplayableDevice) {
        let viewController = EditDeviceNameViewController(
            oldName: device.displayName
        ) { [weak viewModel] newName in
            try await viewModel?.renameDevice(device, to: newName)
            self.presentToast(text: OWSLocalizedString(
                "LINKED_DEVICES_RENAME_SUCCESS_MESSAGE",
                value: "Device name updated",
                comment: "Message on a toast indicating the device was renamed."
            ))
        }
        self.navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: Unlinking

    private func showUnlinkDeviceConfirmAlert(displayableDevice: LinkedDevicesViewModel.DisplayableDevice) {
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
                style: .destructive,
                handler: { [weak viewModel] _ in
                    viewModel?.unlinkDevice(displayableDevice.device)
                }
            )
        )
        alert.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(alert)
    }

    private func showUnlinkFailedAlert(device: OWSDevice, error: Error) {
        AssertIsOnMainThread()

        let title = OWSLocalizedString(
            "UNLINKING_FAILED_ALERT_TITLE",
            comment: "Alert title when unlinking device fails"
        )
        let alert = ActionSheetController(title: title, message: error.userErrorDescription)
        alert.addAction(
            ActionSheetAction(
                title: CommonStrings.retryButton,
                style: .default
            ) { [weak self] _ in
                self?.viewModel.unlinkDevice(device)
            }
        )
        alert.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(alert)
    }
}

// MARK: - LinkedDevicesView

struct LinkedDevicesView: View {
    @ObservedObject var viewModel: LinkedDevicesViewModel

    private var isEditing: Bool {
        viewModel.editMode.isEditing
    }

    var body: some View {
        SignalList {
            SignalSection {
                VStack(spacing: 20) {
                    Image("linked-device-intro-dark")

                    Text(OWSLocalizedString(
                        "LINKED_DEVICES_HEADER_DESCRIPTION",
                        comment: "Description for header of the linked devices list"
                    ))
                        .appendLink(CommonStrings.learnMore) {
                            viewModel.present.send(.linkedDeviceEducation)
                        }
                        .foregroundStyle(Color.Signal.secondaryLabel)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    Button {
                        viewModel.present.send(.linkDeviceAuthentication)
                    } label: {
                        Text(OWSLocalizedString(
                            "LINK_NEW_DEVICE_TITLE",
                            comment: "Navigation title when scanning QR code to add new device."
                        ))
                    }
                    .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
                    .disabled(isEditing)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }

            SignalSection {
                if viewModel.displayableDevices.isEmpty {
                    ZStack(alignment: .center) {
                        // For height calculation
                        DeviceView(device: nil)
                            .opacity(0)

                        if viewModel.isLoading {
                            // [Device Linking] TODO: Signal spinner
                            ProgressView()
                        } else {
                            Text(OWSLocalizedString(
                                "LINKED_DEVICES_EMPTY_STATE",
                                comment: "Text that appears where the linked device list would be indicating that there are no linked devices."
                            ))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                ForEach(viewModel.displayableDevices, id: \.self) { device in
                    DeviceView(device: device)
                        .swipeActions {
                            Button(Self.unlinkString) {
                                viewModel.present.send(.unlinkDeviceConfirmation(displayableDevice: device))
                            }
                            .tint(.red)
                        }
                }
                .onDelete { _ in
                    // This exists for adding the (-) buttons in edit mode,
                    // but the actual swipe action is defined above.
                }
            } header: {
                Text(OWSLocalizedString(
                    "LINKED_DEVICES_LIST_TITLE",
                    comment: "Title above the list of currently-linked devices"
                ))
            } footer: {
                (
                    SignalSymbol.lock.text(dynamicTypeBaseSize: 16).baselineOffset(-1) +
                    Text(" ") +
                    Text(OWSLocalizedString(
                        "LINKED_DEVICES_LIST_FOOTER",
                        comment: "Footer text below the list of currently-linked devices"
                    ))
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .font(.caption)
                .padding(.top)
            }

            if shouldShowDeviceIdsBecauseUserIsInternal {
                SignalSection { } footer: {
                    Text(LocalizationNotNeeded(
                        "Device IDs (and this message) are only shown to internal users."
                    ))
                    .foregroundStyle(Color.Signal.tertiaryLabel)
                }
            }
        }
        .task {
            await viewModel.refreshDevices()
        }
        .refreshable {
            await viewModel.refreshDevices()
        }
        .environment(\.editMode, self.$viewModel.editMode)
        .environmentObject(viewModel)
    }

    // MARK: DeviceView

    private struct DeviceView: View {
        @EnvironmentObject private var viewModel: LinkedDevicesViewModel

        var device: LinkedDevicesViewModel.DisplayableDevice?

        private var deviceName: String {
            if let device {
                if shouldShowDeviceIdsBecauseUserIsInternal {
                    LocalizationNotNeeded(
                        "#\(device.device.deviceId): \(device.displayName)"
                    )
                } else {
                    device.displayName
                }
            } else {
                " "
            }
        }

        private func dateFormattedString(format: String, date: Date) -> String {
            String(
                format: format,
                DateUtil.dateFormatter.string(from: date)
            )
        }

        private var linkedDateString: String {
            guard let device else { return " " }
            return dateFormattedString(
                format: OWSLocalizedString(
                    "DEVICE_LINKED_AT_LABEL",
                    comment: "{{Short Date}} when device was linked."
                ),
                date: device.device.createdAt
            )
        }

        private var lastSeenDateString: String {
            guard let device else { return " " }
            return dateFormattedString(
                format: OWSLocalizedString(
                    "DEVICE_LAST_ACTIVE_AT_LABEL",
                    comment: "{{Short Date}} when device last communicated with Signal Server."
                ),
                // lastSeenAt is stored at day granularity. At midnight UTC.
                // Making it likely that when you first link a device it will
                // be "last seen" the day before it was created, which looks broken.
                date: max(
                    device.device.createdAt,
                    device.device.lastSeenAt
                )
            )
        }

        var body: some View {
            HStack(spacing: 12) {
                Image("devices")
                    .padding(6)
                    .background(Color(.systemFill), in: .circle)

                VStack(alignment: .leading) {
                    Text(self.deviceName)
                    Group {
                        Text(linkedDateString)
                        Text(lastSeenDateString)
                    }
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }

                Spacer(minLength: 0)

                Menu {
                    Button {
                        guard let device else { return }
                        viewModel.present.send(
                            .unlinkDeviceConfirmation(displayableDevice: device)
                        )
                    } label: {
                        Label(LinkedDevicesView.unlinkString, image: "link-slash")
                    }

                    Button {
                        guard let device else { return }
                        viewModel.present.send(
                            .renameDevice(displayableDevice: device)
                        )
                    } label: {
                        Label(
                            OWSLocalizedString(
                                "LINKED_DEVICES_RENAME_BUTTON",
                                comment: "Button title for renaming a linked device"
                            ),
                            image: "edit"
                        )
                    }
                } label: {
                    VStack(spacing: 0) {
                        Label(CommonStrings.editButton, image: "more-vertical")
                            .labelStyle(.iconOnly)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, 9)
                .foregroundStyle(.primary)
            }
        }
    }

    private static let unlinkString = OWSLocalizedString(
        "UNLINK_ACTION",
        comment: "button title for unlinking a device"
    )
}

// MARK: - EditDeviceNameViewController

class EditDeviceNameViewController: NameEditorViewController {
    override class var nameByteLimit: Int { 225 }
    override class var nameGlyphLimit: Int { 50 }

    override var placeholderText: String? {
        OWSLocalizedString(
            "SECONDARY_ONBOARDING_CHOOSE_DEVICE_NAME_PLACEHOLDER",
            comment: "text field placeholder"
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = OWSLocalizedString(
            "LINKED_DEVICES_RENAME_TITLE",
            comment: "Title for the screen for renaming a linked device"
        )
    }

    override func handleError(_ error: any Error) {
        OWSActionSheets.showErrorAlert(
            message: OWSLocalizedString(
                "LINKED_DEVICES_RENAME_FAILURE_MESSAGE",
                comment: "Message on a sheet indicating the device rename attempt received an error."
            )
        )
    }
}

// MARK: - Previews

#if DEBUG
@available(iOS 17, *)
#Preview {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        await MockSSKEnvironment.activate()
        semaphore.signal()
    }
    semaphore.wait()
    let viewController = LinkedDevicesHostingController(isPreview: true)
    return OWSNavigationController(rootViewController: viewController)
}
#endif
