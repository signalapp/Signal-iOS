// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Photos
import PhotosUI
import SessionUtilitiesKit

public enum Permissions {
    public static func requestCameraPermissionIfNeeded(
        presentingViewController: UIViewController? = nil
    ) -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return true
            case .denied, .restricted:
                guard let presentingViewController: UIViewController = (presentingViewController ?? CurrentAppContext().frontmostViewController()) else { return false }
                
                let confirmationModal: ConfirmationModal = ConfirmationModal(
                    info: ConfirmationModal.Info(
                        title: "Session",
                        explanation: String(
                            format: "modal_permission_explanation".localized(),
                            "modal_permission_camera".localized()
                        ),
                        confirmTitle: "modal_permission_settings_title".localized(),
                        dismissOnConfirm: false
                    ) { [weak presentingViewController] _ in
                        presentingViewController?.dismiss(animated: true, completion: {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        })
                    }
                )
                presentingViewController.present(confirmationModal, animated: true, completion: nil)
                return false
                
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { _ in })
                return false
                
            default: return false
        }
    }

    public static func requestMicrophonePermissionIfNeeded(
        presentingViewController: UIViewController? = nil,
        onNotGranted: (() -> Void)? = nil
    ) {
        switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: break
            case .denied:
                guard let presentingViewController: UIViewController = (presentingViewController ?? CurrentAppContext().frontmostViewController()) else { return }
                onNotGranted?()
                
                let confirmationModal: ConfirmationModal = ConfirmationModal(
                    info: ConfirmationModal.Info(
                        title: "Session",
                        explanation: String(
                            format: "modal_permission_explanation".localized(),
                            "modal_permission_microphone".localized()
                        ),
                        confirmTitle: "modal_permission_settings_title".localized(),
                        dismissOnConfirm: false,
                        onConfirm: { [weak presentingViewController] _ in
                            presentingViewController?.dismiss(animated: true, completion: {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            })
                        },
                        afterClosed: { onNotGranted?() }
                    )
                )
                presentingViewController.present(confirmationModal, animated: true, completion: nil)
                
            case .undetermined:
                onNotGranted?()
                AVAudioSession.sharedInstance().requestRecordPermission { _ in }
                
            default: break
        }
    }

    public static func requestLibraryPermissionIfNeeded(
        presentingViewController: UIViewController? = nil,
        onAuthorized: @escaping () -> Void
    ) {
        let authorizationStatus: PHAuthorizationStatus
        if #available(iOS 14, *) {
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if authorizationStatus == .notDetermined {
                // When the user chooses to select photos (which is the .limit status),
                // the PHPhotoUI will present the picker view on the top of the front view.
                // Since we have the ScreenLockUI showing when we request premissions,
                // the picker view will be presented on the top of the ScreenLockUI.
                // However, the ScreenLockUI will dismiss with the permission request alert view, so
                // the picker view then will dismiss, too. The selection process cannot be finished
                // this way. So we add a flag (isRequestingPermission) to prevent the ScreenLockUI
                // from showing when we request the photo library permission.
                Environment.shared?.isRequestingPermission = true
                
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    Environment.shared?.isRequestingPermission = false
                    if [ PHAuthorizationStatus.authorized, PHAuthorizationStatus.limited ].contains(status) {
                        onAuthorized()
                    }
                }
            }
        }
        else {
            authorizationStatus = PHPhotoLibrary.authorizationStatus()
            if authorizationStatus == .notDetermined {
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        onAuthorized()
                    }
                }
            }
        }
        
        switch authorizationStatus {
            case .authorized, .limited: onAuthorized()
            case .denied, .restricted:
                guard let presentingViewController: UIViewController = (presentingViewController ?? CurrentAppContext().frontmostViewController()) else { return }
                
                let confirmationModal: ConfirmationModal = ConfirmationModal(
                    info: ConfirmationModal.Info(
                        title: "Session",
                        explanation: String(
                            format: "modal_permission_explanation".localized(),
                            "modal_permission_library".localized()
                        ),
                        confirmTitle: "modal_permission_settings_title".localized(),
                        dismissOnConfirm: false
                    ) { [weak presentingViewController] _ in
                        presentingViewController?.dismiss(animated: true, completion: {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        })
                    }
                )
                presentingViewController.present(confirmationModal, animated: true, completion: nil)
                
            default: return
        }
    }
}
