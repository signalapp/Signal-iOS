//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Photos
import SignalCoreKit
import SignalMessaging
import SignalServiceKit

extension UIViewController {

    public func ows_askForCameraPermissions(callback: @escaping (Bool) -> Void) {
        Logger.verbose("\(String(describing: Self.self)) ows_askForCameraPermissions")

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
                message: OWSLocalizedString("MISSING_CAMERA_PERMISSION_MESSAGE", comment: "Alert body")
            )
            if let openSettingsAction = AppContextUtils.openSystemSettingsAction(completion: { threadSafeCallback(false) }) {
                actionSheet.addAction(openSettingsAction)
            }
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.dismissButton,
                style: .cancel,
                handler: { _ in
                    threadSafeCallback(false)
                }
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

        default:
            Logger.error("Unknown AVAuthorizationStatus: \(authorizationStatus)")
            threadSafeCallback(false)
        }
    }

    public func ows_askForMediaLibraryPermissions(callback: @escaping (Bool) -> Void) {
        Logger.verbose("\(String(describing: Self.self)) ows_askForMediaLibraryPermissions")

        // Ensure callback is invoked on main thread.
        let threadSafeCallback: (Bool) -> Void = { granted in
            DispatchMainThreadSafe {
                callback(granted)
            }
        }

        guard CurrentAppContext().reportedApplicationState != .background else {
            Logger.error("Skipping media library permissions request when app is in background.")
            threadSafeCallback(false)
            return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            Logger.error("PhotoLibrary ImagePicker source not available")
            threadSafeCallback(false)
            return
        }

        let presentSettingsDialog = {
            AssertIsOnMainThread()

            let actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "MISSING_MEDIA_LIBRARY_PERMISSION_TITLE",
                    comment: "Alert title when user has previously denied media library access"
                ),
                message: OWSLocalizedString(
                    "MISSING_MEDIA_LIBRARY_PERMISSION_MESSAGE",
                    comment: "Alert body when user has previously denied media library access"
                )
            )

            if let openSettingsAction = AppContextUtils.openSystemSettingsAction(completion: { threadSafeCallback(false) }) {
                actionSheet.addAction(openSettingsAction)
            }
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.dismissButton,
                style: .cancel,
                handler: { _ in
                    threadSafeCallback(false)
                }
            ))
            self.presentActionSheet(actionSheet)
        }

        let authorizationStatus = PHPhotoLibrary.authorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { status in
                switch status {
                case .authorized, .limited:
                    threadSafeCallback(true)
                default:
                    DispatchMainThreadSafe { presentSettingsDialog() }
                }
            }
        case .denied, .restricted:
            DispatchMainThreadSafe { presentSettingsDialog() }

        case .authorized, .limited:
            threadSafeCallback(true)

        @unknown default:
            owsFail("Unknown authorization status \(authorizationStatus)")
        }
    }

    public func ows_askForMicrophonePermissions(callback: @escaping (Bool) -> Void) {
        Logger.verbose("\(String(describing: Self.self)) ows_askForMicrophonePermissions")

        // Ensure callback is invoked on main thread.
        let threadSafeCallback: (Bool) -> Void = { granted in
            DispatchMainThreadSafe {
                callback(granted)
            }
        }

        // We want to avoid asking for audio permission while the app is in the background,
        // as WebRTC can ask at some strange times. However, if we're currently in a call
        // it's important we allow you to request audio permission regardless of app state.
        guard CurrentAppContext().reportedApplicationState != .background || CurrentAppContext().hasActiveCall else {
            Logger.error("Skipping microphone permissions request when app is in background.")
            threadSafeCallback(false)
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission(threadSafeCallback)
    }

    public func ows_showNoMicrophonePermissionActionSheet() {
        DispatchMainThreadSafe {
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "CALL_AUDIO_PERMISSION_TITLE",
                    comment: "Alert title when calling and permissions for microphone are missing"
                ),
                message: OWSLocalizedString(
                    "CALL_AUDIO_PERMISSION_MESSAGE",
                    comment: "Alert message when calling and permissions for microphone are missing"
                )
            )

            if let openSettingsAction = AppContextUtils.openSystemSettingsAction() {
                actionSheet.addAction(openSettingsAction)
            }
            actionSheet.addAction(OWSActionSheets.dismissAction)
            self.presentActionSheet(actionSheet)
        }
    }
}
