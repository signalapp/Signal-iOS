//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

extension ChatListViewController: CameraFirstCaptureDelegate {

    @objc
    func showCameraView() {
        // Dismiss any message actions if they're presented
        conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)

        ows_askForCameraPermissions { cameraAccessGranted in
            guard cameraAccessGranted else {
                Logger.warn("Camera permission denied")
                return
            }
            self.ows_askForMicrophonePermissions { microphoneAccessGranted in
                if !microphoneAccessGranted {
                    // We can still continue without mic permissions, but any captured video will
                    // be silent.
                    Logger.warn("Proceeding with no microphone access.")
                }

                let cameraModal = CameraFirstCaptureNavigationController.cameraFirstModal(delegate: self)
                cameraModal.modalPresentationStyle = .overFullScreen

                // Defer hiding status bar until modal is fully onscreen
                // to prevent unwanted shifting upwards of the entire presenter VC's view.
                let modalHidesStatusBar = cameraModal.topViewController?.prefersStatusBarHidden ?? false
                if !modalHidesStatusBar {
                    cameraModal.modalPresentationCapturesStatusBarAppearance = true
                }
                self.present(cameraModal, animated: true, completion: {
                    if modalHidesStatusBar {
                        cameraModal.modalPresentationCapturesStatusBarAppearance = true
                        cameraModal.setNeedsStatusBarAppearanceUpdate()
                    }
                })
            }
        }
    }

    func cameraFirstCaptureSendFlowDidComplete(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow) {
        dismiss(animated: true)
    }

    func cameraFirstCaptureSendFlowDidCancel(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow) {
        dismiss(animated: true)
    }
}
