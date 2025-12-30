//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
public import Photos
import SignalServiceKit

extension UIViewController {

    public func ows_askForCameraPermissions(callback: @escaping (Bool) -> Void) {
        // Ensure callback is invoked on main thread.
        let threadSafeCallback: (Bool) -> Void = { granted in
            DispatchMainThreadSafe {
                callback(granted)
            }
        }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) || Platform.isSimulator else {
            Logger.error("Camera ImagePicker source not available")
            threadSafeCallback(false)
            return
        }

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        guard CurrentAppContext().reportedApplicationState != .background else {
            Logger.warn("Skipping camera permissions request when app is in background, relying on previous status \(authorizationStatus.rawValue)")
            threadSafeCallback(authorizationStatus == .authorized)
            return
        }

        let presentSettingsDialog = {
            AssertIsOnMainThread()

            let actionSheet = ActionSheetController(
                title: OWSLocalizedString("MISSING_CAMERA_PERMISSION_TITLE", comment: "Alert title"),
                message: OWSLocalizedString("MISSING_CAMERA_PERMISSION_MESSAGE", comment: "Alert body"),
            )
            if let openSettingsAction = AppContextUtils.openSystemSettingsAction(completion: { threadSafeCallback(false) }) {
                actionSheet.addAction(openSettingsAction)
            }
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.dismissButton,
                style: .cancel,
                handler: { _ in
                    threadSafeCallback(false)
                },
            ))
            self.presentActionSheet(actionSheet)
        }

        switch authorizationStatus {
        case .denied:
            DispatchMainThreadSafe { presentSettingsDialog() }

        case .authorized:
            threadSafeCallback(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: threadSafeCallback)

        case .restricted:
            threadSafeCallback(false)

        @unknown default:
            Logger.error("Unknown AVAuthorizationStatus: \(authorizationStatus)")
            threadSafeCallback(false)
        }
    }

    public func askForCameraPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            self.ows_askForCameraPermissions { continuation.resume(returning: $0) }
        }
    }

    public func ows_askForMediaLibraryPermissions(callback: @escaping (Bool) -> Void) {
        Task {
            callback(await self.ows_askForMediaLibraryPermissions(for: .readWrite))
        }
    }

    @MainActor
    public func ows_askForMediaLibraryPermissions(for accessLevel: PHAccessLevel) async -> Bool {
        guard CurrentAppContext().reportedApplicationState != .background else {
            Logger.error("Skipping media library permissions request when app is in background.")
            return false
        }

        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            Logger.error("PhotoLibrary ImagePicker source not available")
            return false
        }

        let authorizationStatus = PHPhotoLibrary.authorizationStatus(for: accessLevel)
        switch authorizationStatus {
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: accessLevel)
            switch status {
            case .authorized, .limited:
                return true
            default:
                await self.presentMediaLibraryAccessDeniedSheet()
                return false
            }

        case .denied, .restricted:
            await self.presentMediaLibraryAccessDeniedSheet()
            return false

        case .authorized, .limited:
            return true

        @unknown default:
            owsFailDebug("Unknown authorization status \(authorizationStatus)")
            return false
        }
    }

    @MainActor
    private func presentMediaLibraryAccessDeniedSheet() async {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "MISSING_MEDIA_LIBRARY_PERMISSION_TITLE",
                comment: "Alert title when user has previously denied media library access",
            ),
            message: OWSLocalizedString(
                "MISSING_MEDIA_LIBRARY_PERMISSION_MESSAGE",
                comment: "Alert body when user has previously denied media library access",
            ),
        )

        return await withCheckedContinuation { continuation in
            if
                let openSettingsAction = AppContextUtils.openSystemSettingsAction(completion: {
                    continuation.resume()
                })
            {
                actionSheet.addAction(openSettingsAction)
            }
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.dismissButton,
                style: .cancel,
                handler: { _ in
                    continuation.resume()
                },
            ))
            self.presentActionSheet(actionSheet)
        }
    }

    public func ows_askForMicrophonePermissions(callback: @escaping (Bool) -> Void) {
        // Ensure callback is invoked on main thread.
        let threadSafeCallback: (Bool) -> Void = { granted in
            DispatchMainThreadSafe {
                callback(granted)
            }
        }

        // We want to avoid asking for audio permission while the app is in the background,
        // as WebRTC can ask at some strange times. However, if we're currently in a call
        // it's important we allow you to request audio permission regardless of app state.
        guard CurrentAppContext().reportedApplicationState != .background || DependenciesBridge.shared.currentCallProvider.hasCurrentCall else {
            Logger.error("Skipping microphone permissions request when app is in background.")
            threadSafeCallback(false)
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission(threadSafeCallback)
    }

    public func askForMicrophonePermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            self.ows_askForMicrophonePermissions { continuation.resume(returning: $0) }
        }
    }

    public func ows_showNoMicrophonePermissionActionSheet() {
        AssertIsOnMainThread()

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "CALL_AUDIO_PERMISSION_TITLE",
                comment: "Alert title when calling and permissions for microphone are missing",
            ),
            message: OWSLocalizedString(
                "CALL_AUDIO_PERMISSION_MESSAGE",
                comment: "Alert message when calling and permissions for microphone are missing",
            ),
        )

        if let openSettingsAction = AppContextUtils.openSystemSettingsAction() {
            actionSheet.addAction(openSettingsAction)
        }
        actionSheet.addAction(OWSActionSheets.dismissAction)
        self.presentActionSheet(actionSheet)
    }
}
