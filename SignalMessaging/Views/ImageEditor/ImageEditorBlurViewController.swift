//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import Vision

public class ImageEditorBlurViewController: OWSViewController {

    private let model: ImageEditorModel

    private let canvasView: ImageEditorCanvasView

    private let autoBlurContainer = UIView()
    private let autoBlurSwitch = UISwitch()

    // We only want to let users undo changes made in this view.
    // So we snapshot any older "operation id" and prevent
    // users from undoing it.
    private let firstUndoOperationId: String?

    init(model: ImageEditorModel) {
        self.model = model
        self.canvasView = ImageEditorCanvasView(model: model)
        self.firstUndoOperationId = model.currentUndoOperationId()

        super.init()

        model.add(observer: self)
    }

    // MARK: - View Lifecycle

    public override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = .black
        self.view.isOpaque = true

        canvasView.configureSubviews()
        self.view.addSubview(canvasView)
        canvasView.autoPinEdgesToSuperviewEdges()

        self.view.isUserInteractionEnabled = true

        let brushGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleBlurGesture))
        brushGestureRecognizer.maximumNumberOfTouches = 1
        brushGestureRecognizer.referenceView = canvasView.gestureReferenceView
        brushGestureRecognizer.delegate = self
        self.view.addGestureRecognizer(brushGestureRecognizer)

        autoBlurContainer.backgroundColor = .ows_blackAlpha60
        autoBlurContainer.layoutMargins = UIEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 8)

        view.addSubview(autoBlurContainer)
        autoBlurContainer.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 16)
        autoBlurContainer.autoHCenterInSuperview()

        let autoBlurLabel = UILabel()
        autoBlurLabel.text = NSLocalizedString("IMAGE_EDITOR_AUTO_BLUR_SETTING", comment: "The image editor setting to automatically blur faces")
        autoBlurLabel.font = .ows_dynamicTypeSubheadlineClamped
        autoBlurLabel.textColor = Theme.darkThemePrimaryColor

        autoBlurContainer.addSubview(autoBlurLabel)
        autoBlurLabel.autoPinLeadingToSuperviewMargin()
        autoBlurLabel.autoPinHeightToSuperviewMargins()

        autoBlurSwitch.addTarget(self, action: #selector(didToggleAutoBlur), for: .valueChanged)
        autoBlurSwitch.isOn = currentAutoBlurItem != nil

        autoBlurContainer.addSubview(autoBlurSwitch)
        autoBlurSwitch.autoPinTrailingToSuperviewMargin()
        autoBlurSwitch.autoPinHeightToSuperviewMargins()
        autoBlurSwitch.autoPinEdge(.leading, to: .trailing, of: autoBlurLabel, withOffset: 10)

        updateNavigationBar()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.view.layoutSubviews()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.view.layoutSubviews()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        view.layoutIfNeeded()

        autoBlurContainer.layer.cornerRadius = autoBlurContainer.height / 2
    }

    private func updateNavigationBar() {
        // Hide controls during blur.
        let hasBlur = currentBlurStroke != nil
        guard !hasBlur else {
            updateNavigationBar(navigationBarItems: [])
            return
        }

        let undoButton = navigationBarButton(imageName: "image_editor_undo",
                                             selector: #selector(didTapUndo(sender:)))
        let doneButton = navigationBarButton(imageName: "image_editor_checkmark_full",
                                             selector: #selector(didTapDone(sender:)))

        // Prevent users from undo any changes made before entering the view.
        let canUndo = model.canUndo() && firstUndoOperationId != model.currentUndoOperationId()
        var navigationBarItems = [UIView]()
        if canUndo {
            navigationBarItems = [undoButton, doneButton]
        } else {
            navigationBarItems = [doneButton]
        }
        updateNavigationBar(navigationBarItems: navigationBarItems)
    }

    private func updateControls() {
        // Hide controls during blur.
        let hasBlur = currentBlurStroke != nil
        autoBlurContainer.isHidden = hasBlur
    }

    @objc
    public override var prefersStatusBarHidden: Bool {
        guard !OWSWindowManager.shared.hasCall else {
            return false
        }

        return true
    }

    // MARK: - Actions

    @objc func didTapUndo(sender: UIButton) {
        Logger.verbose("")
        guard model.canUndo() else {
            owsFailDebug("Can't undo.")
            return
        }
        model.undo()
    }

    @objc func didTapDone(sender: UIButton) {
        Logger.verbose("")

        completeAndDismiss()
    }

    private func completeAndDismiss() {
        self.dismiss(animated: false)
    }

    // We persist an auto blur identifier for this session so
    // we can keep the toggle switch in sync with undo/redo behavior
    private static let autoBlurItemIdentifier = "autoBlur"
    private var currentAutoBlurItem: ImageEditorBlurRegionsItem? {
        return model.item(forId: ImageEditorBlurViewController.autoBlurItemIdentifier) as? ImageEditorBlurRegionsItem
    }

    @objc func didToggleAutoBlur(sender: UISwitch) {
        Logger.verbose("")

        if let currentAutoBlurItem = currentAutoBlurItem {
            model.remove(item: currentAutoBlurItem)
        }

        guard sender.isOn else { return }

        guard let srcImage = ImageEditorCanvasView.loadSrcImage(model: model),
            let srcCGImage = srcImage.cgImage else {
            return
        }

        // TODO: Display a toast on error / no faces detected

        let cgOrientation = CGImagePropertyOrientation(srcImage.imageOrientation)

        let request = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                owsFailDebug("Face Detection Error \(error)")
                return
            }
            // Perform drawing on the main thread.
            DispatchQueue.main.async {
                guard let results = request.results as? [VNFaceObservation] else { return }

                Logger.verbose("Detected \(results.count) faces")

                func unitBoundingBox(_ faceObservation: VNFaceObservation) -> CGRect {
                    var unitRect = faceObservation.boundingBox
                    unitRect.origin.y = 1 - unitRect.origin.y - unitRect.height
                    return unitRect
                }

                let autoBlurItem = ImageEditorBlurRegionsItem(
                    itemId: ImageEditorBlurViewController.autoBlurItemIdentifier,
                    unitBoundingBoxes: results.map(unitBoundingBox)
                )
                self.model.append(item: autoBlurItem)
            }
        }
        let imageRequestHandler = VNImageRequestHandler(cgImage: srcCGImage,
                                                        orientation: cgOrientation,
                                                        options: [:])

        // Send the requests to the request handler.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try imageRequestHandler.perform([request])
            } catch let error as NSError {
                owsFailDebug("Failed to perform image request: \(error)")
                return
            }
        }
    }

    // MARK: - Blur

    // These properties are non-empty while drawing a blur.
    private var currentBlurStroke: ImageEditorStrokeItem? {
        didSet {
            updateControls()
            updateNavigationBar()
        }
    }
    private var currentBlurStrokeSamples = [ImageEditorStrokeItem.StrokeSample]()

    @objc
    public func handleBlurGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        func removeCurrentBlur() {
            if let blur = self.currentBlurStroke {
                self.model.remove(item: blur)
            }
            self.currentBlurStroke = nil
            self.currentBlurStrokeSamples.removeAll()
        }
        func tryToAppendBlurSample(_ locationInView: CGPoint) {
            let view = self.canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let newSample = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
                                                                    viewBounds: viewBounds,
                                                                    model: self.model,
                                                                    transform: self.model.currentTransform())

            if let prevSample = self.currentBlurStrokeSamples.last,
                prevSample == newSample {
                // Ignore duplicate samples.
                return
            }
            self.currentBlurStrokeSamples.append(newSample)
        }

        let unitBlurStrokeWidth = 0.05 / self.model.currentTransform().scaling

        switch gestureRecognizer.state {
        case .began:
            removeCurrentBlur()

            // Apply the location history of the gesture so that the blur reflects
            // the touch's movement before the gesture recognized.
            for location in gestureRecognizer.locationHistory {
                tryToAppendBlurSample(location)
            }

            let locationInView = gestureRecognizer.location(in: canvasView.gestureReferenceView)
            tryToAppendBlurSample(locationInView)

            let blur = ImageEditorStrokeItem(isBlur: true, unitSamples: currentBlurStrokeSamples, unitStrokeWidth: unitBlurStrokeWidth)
            model.append(item: blur)
            currentBlurStroke = blur

        case .changed, .ended:
            let locationInView = gestureRecognizer.location(in: canvasView.gestureReferenceView)
            tryToAppendBlurSample(locationInView)

            guard let lastBlur = self.currentBlurStroke else {
                owsFailDebug("Missing last blur.")
                removeCurrentBlur()
                return
            }

            // Model items are immutable; we _replace_ the
            // blur item rather than modify it.
            let blurStroke = ImageEditorStrokeItem(itemId: lastBlur.itemId, isBlur: true, unitSamples: currentBlurStrokeSamples, unitStrokeWidth: unitBlurStrokeWidth)
            model.replace(item: blurStroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                currentBlurStroke = nil
                currentBlurStrokeSamples.removeAll()
            } else {
                currentBlurStroke = blurStroke
            }
        default:
            removeCurrentBlur()
        }
    }
}

// MARK: -

extension ImageEditorBlurViewController: ImageEditorModelObserver {

    public func imageEditorModelDidChange(before: ImageEditorContents,
                                          after: ImageEditorContents) {
        updateNavigationBar()

        // If we undo/redo, we may remove or re-apply the auto blur
        autoBlurSwitch.isOn = currentAutoBlurItem != nil
    }

    public func imageEditorModelDidChange(changedItemIds: [String]) {
        updateNavigationBar()
    }
}

// MARK: -

extension ImageEditorBlurViewController: UIGestureRecognizerDelegate {
    @objc public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ignore touches that begin inside the autoBlurContainer.
        let location = touch.location(in: autoBlurContainer)
        return !autoBlurContainer.bounds.contains(location)
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
