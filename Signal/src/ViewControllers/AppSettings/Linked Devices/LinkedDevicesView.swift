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

class LinkedDevicesViewModel: ObservableObject {

    @Published fileprivate var editMode: EditMode = .inactive
    @Published fileprivate var displayableDevices: [DisplayableDevice] = []
    @Published fileprivate var isLoading: Bool = false

    fileprivate enum Presentation {
        case newDeviceToast(deviceName: String)
        case linkDeviceAuthentication(preknownProvisioningUrl: DeviceProvisioningURL?)
        case unlinkDeviceConfirmation(displayableDevice: DisplayableDevice)
        case updateFailureAlert(Error)
        case unlinkFailureAlert(device: OWSDevice, error: Error)
        case activityIndicator(ModalActivityIndicatorViewController)
        case linkedDeviceEducation
    }

    fileprivate var present = PassthroughSubject<Presentation, Never>()

    private var subscriptions = Set<AnyCancellable>()
    private var pollingRefreshTimer: Timer?
    private var oldDeviceList: [DisplayableDevice] = []
    private var isExpectingMoreDevices = false {
        didSet {
            shouldShowFinishLinkingSheet = isExpectingMoreDevices
        }
    }
    fileprivate var shouldShowFinishLinkingSheet = false

    init() {
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        NotificationCenter.default.publisher(
            for: OWSDevicesService.deviceListUpdateFailed
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let error = notification.object as? Error else {
                owsFailDebug("Missing error.")
                return
            }
            if error.isNetworkFailureOrTimeout {
                return
            }

            self?.present.send(.updateFailureAlert(error))
        }
        .store(in: &subscriptions)

        NotificationCenter.default.publisher(
            for: OWSDevicesService.deviceListUpdateModifiedDeviceList
        )
        .sink { [weak self] _ in
            self?.pollingRefreshTimer?.invalidate()
            self?.pollingRefreshTimer = nil
        }
        .store(in: &subscriptions)
    }

    @MainActor
    func refreshDevices() async {
        if displayableDevices.isEmpty {
            self.isLoading = true
        }

        try? await OWSDevicesService.refreshDevices().awaitable()

        if !isExpectingMoreDevices {
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
                isExpectingMoreDevices,
                let newDevice = displayableDevices.last,
                newDevice != oldDeviceList.last
            {
                present.send(.newDeviceToast(deviceName: newDevice.displayName))
                isExpectingMoreDevices = false
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
        OWSDevicesService.unlinkDevice(
            device,
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
                    self?.present.send(.unlinkFailureAlert(device: device, error: error))
                }
            }
        )
    }

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

// MARK: LinkDeviceViewControllerDelegate

extension LinkedDevicesViewModel: LinkDeviceViewControllerDelegate {
    func didFinishLinking(linkNSyncTask: Task<Void, Error>?) {
        guard let linkNSyncTask else {
            expectMoreDevices()
            return
        }
        Task { @MainActor in
            // TODO: use the appropriate UX for loading, and show percent progress
            let loadingViewController = ModalActivityIndicatorViewController(canCancel: false, presentationDelay: 0)
            loadingViewController.modalPresentationStyle = .overFullScreen
            self.present.send(.activityIndicator(loadingViewController))
            do {
                try await linkNSyncTask.value
            } catch {
                loadingViewController.dismiss(animated: false) {
                    DependenciesBridge.shared.messageBackupErrorPresenter.presentOverTopmostViewController(completion: {})
                }
                self.expectMoreDevices()
                return
            }
            await self.refreshDevices()
            loadingViewController.dismiss(animated: false)
        }
    }

    private func expectMoreDevices() {
        AssertIsOnMainThread()

        isExpectingMoreDevices = true
        editMode = .inactive

        pollingRefreshTimer?.invalidate()
        pollingRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            guard let self, self.isExpectingMoreDevices else {
                timer.invalidate()
                return
            }

            Task {
                await self.refreshDevices()
            }
        }
    }
}

// MARK: - LinkedDevicesHostingController

class LinkedDevicesHostingController: HostingContainer<LinkedDevicesView> {
    enum PresentationOnFirstAppear {
        case linkNewDevice(preknownProvisioningUrl: DeviceProvisioningURL)
    }

    private let viewModel = LinkedDevicesViewModel()

    private var presentationOnFirstAppear: PresentationOnFirstAppear?
    private var subscriptions = Set<AnyCancellable>()

    private weak var finishLinkingSheet: HeroSheetViewController?

    init(presentationOnFirstAppear: PresentationOnFirstAppear? = nil) {
        self.presentationOnFirstAppear = presentationOnFirstAppear

        super.init(wrappedView: LinkedDevicesView(viewModel: viewModel))

        OWSTableViewController2.removeBackButtonText(viewController: self)

        viewModel.present.sink { [weak self] presentation in
            guard let self else { return }
            switch presentation {
            case let .newDeviceToast(deviceName):
                if let finishLinkingSheet {
                    finishLinkingSheet.dismiss(animated: true) {
                        self.showNewDeviceToast(deviceName: deviceName)
                    }
                } else {
                    self.showNewDeviceToast(deviceName: deviceName)
                }
            case let .updateFailureAlert(error):
                self.showUpdateFailureAlert(error: error)
            case .linkDeviceAuthentication(let preknownProvisioingUrl):
                self.didTapLinkDeviceButton(preknownProvisioningUrl: preknownProvisioingUrl)
            case let .unlinkDeviceConfirmation(displayableDevice):
                self.showUnlinkDeviceConfirmAlert(displayableDevice: displayableDevice)
            case let .unlinkFailureAlert(device, error):
                self.showUnlinkFailedAlert(device: device, error: error)
            case let .activityIndicator(modal):
                self.present(modal, animated: false)
            case .linkedDeviceEducation:
                self.present(LinkedDevicesEducationSheet(), animated: true)
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

    private func showNewDeviceToast(deviceName: String) {
        presentToast(text: String(
            format: OWSLocalizedString(
                "DEVICE_LIST_UPDATE_NEW_DEVICE_TOAST",
                comment: "Message appearing on a toast indicating a new device was successfully linked. Embeds {{ device name }}"
            ),
            deviceName
        ))
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

    func showUnlinkFailedAlert(device: OWSDevice, error: Error) {
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
                            Button(OWSLocalizedString(
                                "UNLINK_ACTION",
                                comment: "button title for unlinking a device"
                            )) {
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
    }

    // MARK: DeviceView

    private struct DeviceView: View {
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
            }
        }
    }
}

// MARK: - Previews

@available(iOS 17, *)
#Preview {
    LinkedDevicesHostingController()
}
