import Photos
import PhotosUI

public func requestCameraPermissionIfNeeded() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .denied, .restricted:
        let modal = PermissionMissingModal(permission: "camera") { }
        modal.modalPresentationStyle = .overFullScreen
        modal.modalTransitionStyle = .crossDissolve
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() }
        presentingVC.present(modal, animated: true, completion: nil)
        return false
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video, completionHandler: { _ in })
        return false
    default: return false
    }
}

public func requestMicrophonePermissionIfNeeded(onNotGranted: @escaping () -> Void) {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted: break
    case .denied:
        onNotGranted()
        let modal = PermissionMissingModal(permission: "microphone") {
            onNotGranted()
        }
        modal.modalPresentationStyle = .overFullScreen
        modal.modalTransitionStyle = .crossDissolve
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() }
        presentingVC.present(modal, animated: true, completion: nil)
    case .undetermined:
        onNotGranted()
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    default: break
    }
}

public func requestLibraryPermissionIfNeeded(onAuthorized: @escaping () -> Void) {
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
            let appMode = AppModeManager.shared.currentAppMode
            // FIXME: Rather than setting the app mode to light and then to dark again once we're done,
            // it'd be better to just customize the appearance of the image picker. There doesn't currently
            // appear to be a good way to do so though...
            AppModeManager.shared.setCurrentAppMode(to: .light)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    AppModeManager.shared.setCurrentAppMode(to: appMode)
                }
                Environment.shared?.isRequestingPermission = false
                if [ PHAuthorizationStatus.authorized, PHAuthorizationStatus.limited ].contains(status) {
                    onAuthorized()
                }
            }
        }
    } else {
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
    case .authorized, .limited:
        onAuthorized()
    case .denied, .restricted:
        let modal = PermissionMissingModal(permission: "library") { }
        modal.modalPresentationStyle = .overFullScreen
        modal.modalTransitionStyle = .crossDissolve
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() }
        presentingVC.present(modal, animated: true, completion: nil)
    default: return
    }
}
