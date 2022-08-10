//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Vision
import UIKit

// MARK: - Blur Tool

extension ImageEditorViewController {

    private func initializeBlurToolUIIfNecessary() {
        guard !blurToolUIInitialized else { return }

        view.addSubview(blurToolbar)
        blurToolbar.autoHCenterInSuperview()
        blurToolbar.autoPinEdge(.bottom, to: .top, of: bottomBar, withOffset: -36)

        view.addGestureRecognizer(blurToolGestureRecognizer)

        blurToolUIInitialized = true
    }

    func updateBlurToolControlsVisibility() {
        blurToolbar.alpha = topBar.alpha
        strokeWidthSliderContainer.alpha = topBar.alpha
    }

    func updateBlurToolUIVisibility() {
        let visible = mode == .blur

        if visible {
            initializeBlurToolUIIfNecessary()
        } else {
            guard blurToolUIInitialized else { return }
        }

        blurToolbar.isHidden = !visible
        blurToolGestureRecognizer.isEnabled = visible

        if visible {
            currentStrokeType = .blur
        }
    }

    @objc
    func didToggleAutoBlur(sender: UISwitch) {
        Logger.verbose("")

        if let currentAutoBlurItem = currentAutoBlurItem {
            model.remove(item: currentAutoBlurItem)
        }

        guard sender.isOn else { return }

        guard let srcImage = ImageEditorCanvasView.loadSrcImage(model: model),
            let srcCGImage = srcImage.cgImage else {
            return
        }

        let cgOrientation = CGImagePropertyOrientation(srcImage.imageOrientation)

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            presentationDelay: 0.5
        ) { modal in
            func showToast() {
                let toastController = ToastController(text: OWSLocalizedString(
                    "IMAGE_EDITOR_BLUR_TOAST",
                    comment: "A toast indicating that you can blur more faces after detection"
                ))
                let bottomInset = self.view.safeAreaInsets.bottom + 90
                toastController.presentToastView(from: .bottom, of: self.view, inset: bottomInset)
            }

            func faceDetectionFailed() {
                DispatchQueue.main.async {
                    sender.isOn = false
                    modal.dismiss { showToast() }
                }
            }

            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    owsFailDebug("Face Detection Error \(error)")
                    return faceDetectionFailed()
                }
                // Perform drawing on the main thread.
                DispatchQueue.main.async {
                    guard let results = request.results as? [VNFaceObservation] else {
                        return faceDetectionFailed()
                    }

                    Logger.verbose("Detected \(results.count) faces")

                    func unitBoundingBox(_ faceObservation: VNFaceObservation) -> CGRect {
                        var unitRect = faceObservation.boundingBox
                        unitRect.origin.y = 1 - unitRect.origin.y - unitRect.height
                        return unitRect
                    }

                    let autoBlurItem = ImageEditorBlurRegionsItem(
                        itemId: ImageEditorViewController.autoBlurItemIdentifier,
                        unitBoundingBoxes: results.map(unitBoundingBox)
                    )
                    self.model.append(item: autoBlurItem)

                    modal.dismiss { showToast() }
                }
            }

            let imageRequestHandler = VNImageRequestHandler(cgImage: srcCGImage,
                                                            orientation: cgOrientation,
                                                            options: [:])

            // Send the requests to the request handler.
            do {
                try imageRequestHandler.perform([request])
            } catch let error as NSError {
                owsFailDebug("Failed to perform image request: \(error)")
                return faceDetectionFailed()
            }
        }
    }

    @objc
    func handleBlurToolGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        owsAssertDebug(mode == .blur, "Incorrect mode [\(mode)]")

        func removeCurrentBlur() {
            if let blur = self.currentStroke {
                self.model.remove(item: blur)
            }
            self.currentStroke = nil
            self.currentStrokeSamples.removeAll()
        }
        func tryToAppendBlurSample(_ locationInView: CGPoint) {
            let view = self.imageEditorView.gestureReferenceView
            let viewBounds = view.bounds
            let newSample = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
                                                                    viewBounds: viewBounds,
                                                                    model: self.model,
                                                                    transform: self.model.currentTransform())

            if let prevSample = self.currentStrokeSamples.last,
                prevSample == newSample {
                // Ignore duplicate samples.
                return
            }
            self.currentStrokeSamples.append(newSample)
        }

        let unitBlurStrokeWidth = currentStrokeUnitWidth()

        switch gestureRecognizer.state {
        case .began:
            removeCurrentBlur()

            // Apply the location history of the gesture so that the blur reflects
            // the touch's movement before the gesture recognized.
            for location in gestureRecognizer.locationHistory {
                tryToAppendBlurSample(location)
            }

            let locationInView = gestureRecognizer.location(in: imageEditorView.gestureReferenceView)
            tryToAppendBlurSample(locationInView)

            let blur = ImageEditorStrokeItem(strokeType: .blur,
                                             unitSamples: currentStrokeSamples,
                                             unitStrokeWidth: unitBlurStrokeWidth)
            model.append(item: blur)
            currentStroke = blur

        case .changed, .ended:
            let locationInView = gestureRecognizer.location(in: imageEditorView.gestureReferenceView)
            tryToAppendBlurSample(locationInView)

            guard let lastBlur = self.currentStroke else {
                owsFailDebug("Missing last blur.")
                removeCurrentBlur()
                return
            }

            // Model items are immutable; we _replace_ the
            // blur item rather than modify it.
            let blurStroke = ImageEditorStrokeItem(itemId: lastBlur.itemId,
                                                   strokeType: .blur,
                                                   unitSamples: currentStrokeSamples,
                                                   unitStrokeWidth: unitBlurStrokeWidth)
            model.replace(item: blurStroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                currentStroke = nil
                currentStrokeSamples.removeAll()
            } else {
                currentStroke = blurStroke
            }

        default:
            removeCurrentBlur()
        }
    }
}

private extension CGImagePropertyOrientation {

    init(_ uiImageOrientation: UIImage.Orientation) {
        switch uiImageOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        default: self = .up
        }
    }
}
