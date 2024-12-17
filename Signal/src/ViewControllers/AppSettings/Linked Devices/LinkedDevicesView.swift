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
        case linkDeviceAuthentication(preknownProvisioningUrl: DeviceProvisioningURL?)
        case renameDevice(displayableDevice: DisplayableDevice)
        case unlinkDeviceConfirmation(displayableDevice: DisplayableDevice)
        case updateFailureAlert(Error)
        case unlinkFailureAlert(device: OWSDevice, error: Error)
        case activityIndicator(UIViewController)
        case linkedDeviceEducation
        case linkAndSyncFailureAlert
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
    fileprivate var shouldShowFinishLinkingSheet = false

    private let databaseChangeObserver: DatabaseChangeObserver
    private let db: any DB
    private let deviceService: OWSDeviceService
    private let deviceStore: OWSDeviceStore
    private let identityManager: OWSIdentityManager
    private let messageBackupErrorPresenter: MessageBackupErrorPresenter

#if DEBUG
    private let isPreview: Bool
#endif

    init(isPreview: Bool = false) {
#if DEBUG
        self.isPreview = isPreview
#endif
        databaseChangeObserver = DependenciesBridge.shared.databaseChangeObserver
        db = DependenciesBridge.shared.db
        deviceService = DependenciesBridge.shared.deviceService
        deviceStore = DependenciesBridge.shared.deviceStore
        identityManager = DependenciesBridge.shared.identityManager
        messageBackupErrorPresenter = DependenciesBridge.shared.messageBackupErrorPresenter

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
                    .init(device: .previewItem(id: 1), displayName: "iPad"),
                    .init(device: .previewItem(id: 2), displayName: "macOS"),
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
        var displayableDevices = SSKEnvironment.shared.databaseStorageRef.read { transaction -> [DisplayableDevice] in
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
        let identityKeyPair = db.read { tx in
            identityManager.identityKeyPair(for: .aci, tx: tx)
        }

        guard let identityKeyPair else {
            throw DeviceRenameError.encryptionFailed
        }

        let encryptedName = try DeviceNames.encryptDeviceName(
            plaintext: newName,
            identityKeyPair: identityKeyPair.keyPair
        ).base64EncodedString()

        try await deviceService.renameDevice(
            device: displayableDevice.device,
            toEncryptedName: encryptedName
        )
    }

    // MARK: DisplayableDevice

    struct DisplayableDevice: Hashable, Identifiable {
        var id: Int { device.deviceId }

        let device: OWSDevice
        let displayName: String

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
        guard let linkNSyncData else {
            linkDeviceViewController.popToLinkedDeviceList { [weak self] in
                self?.expectMoreDevices()
            }
            return
        }

        // Don't wait for the view pop to start the linking process
        let linkAndSyncProgressModal = LinkAndSyncProgressModal()
        linkDeviceViewController.popToLinkedDeviceList { [weak self] in
            self?.present.send(.activityIndicator(linkAndSyncProgressModal))
        }

        let progress = OWSProgress.createSink { progress in
            Task { @MainActor in
                linkAndSyncProgressModal.progress = progress.percentComplete
            }
        }

        Task { @MainActor in
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
                    self.present.send(.linkAndSyncFailureAlert)
                }
                self.expectMoreDevices()
                return
            }
            self.newDeviceExpectation = .linkAndSync
            await self.refreshDevices()
        }
    }

    private func expectMoreDevices() {
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
}

// MARK: - LinkedDevicesHostingController

class LinkedDevicesHostingController: HostingContainer<LinkedDevicesView> {
    enum PresentationOnFirstAppear {
        case linkNewDevice(preknownProvisioningUrl: DeviceProvisioningURL)
    }

    private let viewModel: LinkedDevicesViewModel

    private var presentationOnFirstAppear: PresentationOnFirstAppear?
    private var subscriptions = Set<AnyCancellable>()

    private weak var finishLinkingSheet: HeroSheetViewController?

    init(
        presentationOnFirstAppear: PresentationOnFirstAppear? = nil,
        isPreview: Bool = false
    ) {
        self.presentationOnFirstAppear = presentationOnFirstAppear
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
            case .linkDeviceAuthentication(let preknownProvisioingUrl):
                self.didTapLinkDeviceButton(preknownProvisioningUrl: preknownProvisioingUrl)
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
            case .linkAndSyncFailureAlert:
                self.showLinkAndSyncFailureAlert()
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

        if let presentationOnFirstAppear {
            self.presentationOnFirstAppear = nil

            switch presentationOnFirstAppear {
            case .linkNewDevice(let preknownProvisioningUrl):
                viewModel.present.send(.linkDeviceAuthentication(preknownProvisioningUrl: preknownProvisioningUrl))
            }
        } else if viewModel.shouldShowFinishLinkingSheet {
            // Only show the sheet once even if viewDidAppear is
            // called multiple times while waiting for the link.
            viewModel.shouldShowFinishLinkingSheet = false

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

    private func showLinkNewDeviceView(preknownProvisioningUrl: DeviceProvisioningURL?) {
        AssertIsOnMainThread()

        func presentLinkView(_ linkView: LinkDeviceViewController) {
            linkView.delegate = viewModel
            navigationController?.pushViewController(linkView, animated: true)
        }

        if let preknownProvisioningUrl {
            presentLinkView(LinkDeviceViewController(preknownProvisioningUrl: preknownProvisioningUrl))
        } else {
            self.ows_askForCameraPermissions { granted in
                guard granted else {
                    return
                }

                presentLinkView(LinkDeviceViewController(preknownProvisioningUrl: nil))
            }
        }
    }

    private func didTapLinkDeviceButton(preknownProvisioningUrl: DeviceProvisioningURL?) {
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
                self.showLinkNewDeviceView(preknownProvisioningUrl: preknownProvisioningUrl)
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
                await self?.authenticateThenShowLinkNewDeviceView(
                    context: context,
                    preknownProvisioningUrl: preknownProvisioningUrl
                )
            }
        }

        self.present(sheet, animated: true)
    }

    private func showLinkAndSyncFailureAlert() {
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
        actionSheet.addAction(.init(title: CommonStrings.learnMore) { _ in
            UIApplication.shared.open(URL(string: "https://support.signal.org/hc/articles/360007320551")!)
        })
        actionSheet.addAction(.init(title: CommonStrings.continueButton, style: .cancel))
        actionSheet.onDismiss = {
            DependenciesBridge.shared.messageBackupErrorPresenter.presentOverTopmostViewController(completion: {})
        }
        presentActionSheet(actionSheet)
    }

    // MARK: Authentication

    private func authenticateThenShowLinkNewDeviceView(
        context: LAContext,
        preknownProvisioningUrl: DeviceProvisioningURL?
    ) async {
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: OWSLocalizedString(
                    "LINK_NEW_DEVICE_AUTHENTICATION_REASON",
                    comment: "Description of how and why Signal iOS uses Touch ID/Face ID/Phone Passcode to unlock device linking."
                )
            )
            self.showLinkNewDeviceView(preknownProvisioningUrl: preknownProvisioningUrl)
        } catch {
            let result = self.handleAuthenticationError(error)
            switch result {
            case .failed(let error):
                self.showError(error)
            case .canceled:
                break
            case .continueWithoutAuthentication:
                self.showLinkNewDeviceView(preknownProvisioningUrl: preknownProvisioningUrl)
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
                accessibilityIdentifier: "confirm_unlink_device",
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

    private var headerSubtitle: String {
        if FeatureFlags.linkAndSync {
            OWSLocalizedString(
                "LINKED_DEVICES_HEADER_DESCRIPTION",
                comment: "Description for header of the linked devices list"
            )
        } else {
            OWSLocalizedString(
                "LINKED_DEVICES_HEADER_DESCRIPTION_LINK_AND_SYNC_DISABLED",
                comment: "Description for header of the linked devices list when Link and Sync is disabled"
            )
        }
    }

    var body: some View {
        SignalList {
            SignalSection {
                VStack(spacing: 20) {
                    Image("linked-device-intro-dark")

                    Text(self.headerSubtitle)
                        .appendLink(CommonStrings.learnMore) {
                            viewModel.present.send(.linkedDeviceEducation)
                        }
                        .foregroundStyle(Color.Signal.secondaryLabel)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    Button {
                        viewModel.present.send(.linkDeviceAuthentication(preknownProvisioningUrl: nil))
                    } label: {
                        Text(OWSLocalizedString(
                            "LINK_NEW_DEVICE_TITLE",
                            comment: "Navigation title when scanning QR code to add new device."
                        ))
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .font(.headline)
                    .buttonStyle(.borderless)
                    .foregroundStyle(isEditing ? Color.Signal.tertiaryLabel : .white)
                    .background(
                        isEditing ? Color.Signal.tertiaryFill : Color.Signal.ultramarine,
                        in: .rect(cornerRadius: 12)
                    )
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
    MockSSKEnvironment.activate()
    let viewController = LinkedDevicesHostingController(isPreview: true)
    return OWSNavigationController(rootViewController: viewController)
}
#endif
