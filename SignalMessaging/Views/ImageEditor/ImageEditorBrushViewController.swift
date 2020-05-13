//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public protocol ImageEditorBrushViewControllerDelegate: class {
    func brushDidComplete(currentColor: ImageEditorColor)
}

// MARK: -

public class ImageEditorBrushViewController: OWSViewController {

    private weak var delegate: ImageEditorBrushViewControllerDelegate?

    private let model: ImageEditorModel

    private let canvasView: ImageEditorCanvasView

    private let paletteView: ImageEditorPaletteView

    // We only want to let users undo changes made in this view.
    // So we snapshot any older "operation id" and prevent
    // users from undoing it.
    private let firstUndoOperationId: String?

    init(delegate: ImageEditorBrushViewControllerDelegate,
         model: ImageEditorModel,
         currentColor: ImageEditorColor) {
        self.delegate = delegate
        self.model = model
        self.canvasView = ImageEditorCanvasView(model: model)
        self.paletteView = ImageEditorPaletteView(currentColor: currentColor)
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

        paletteView.delegate = self
        self.view.addSubview(paletteView)
        paletteView.autoVCenterInSuperview()
        paletteView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 0)

        self.view.isUserInteractionEnabled = true

        let brushGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleBrushGesture(_:)))
        brushGestureRecognizer.maximumNumberOfTouches = 1
        brushGestureRecognizer.referenceView = canvasView.gestureReferenceView
        brushGestureRecognizer.delegate = self
        self.view.addGestureRecognizer(brushGestureRecognizer)

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

    private func updateNavigationBar() {
        // Hide controls during stroke.
        let hasStroke = currentStroke != nil
        guard !hasStroke else {
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
        // Hide controls during stroke.
        let hasStroke = currentStroke != nil
        paletteView.isHidden = hasStroke
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
        self.delegate?.brushDidComplete(currentColor: paletteView.selectedValue)

        self.dismiss(animated: false) {
            // Do nothing.
        }
    }

    // MARK: - Brush

    // These properties are non-empty while drawing a stroke.
    private var currentStroke: ImageEditorStrokeItem? {
        didSet {
            updateControls()
            updateNavigationBar()
        }
    }
    private var currentStrokeSamples = [ImageEditorStrokeItem.StrokeSample]()

    @objc
    public func handleBrushGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        let removeCurrentStroke = {
            if let stroke = self.currentStroke {
                self.model.remove(item: stroke)
            }
            self.currentStroke = nil
            self.currentStrokeSamples.removeAll()
        }
        let tryToAppendStrokeSample = { (locationInView: CGPoint) in
            let view = self.canvasView.gestureReferenceView
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

        let strokeColor = paletteView.selectedValue.color
        let unitStrokeWidth = ImageEditorStrokeItem.defaultUnitStrokeWidth() / self.model.currentTransform().scaling

        switch gestureRecognizer.state {
        case .began:
            removeCurrentStroke()

            // Apply the location history of the gesture so that the stroke reflects
            // the touch's movement before the gesture recognized.
            for location in gestureRecognizer.locationHistory {
                tryToAppendStrokeSample(location)
            }

            let locationInView = gestureRecognizer.location(in: canvasView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            let stroke = ImageEditorStrokeItem(color: strokeColor, unitSamples: currentStrokeSamples, unitStrokeWidth: unitStrokeWidth)
            model.append(item: stroke)
            currentStroke = stroke

        case .changed, .ended:
            let locationInView = gestureRecognizer.location(in: canvasView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            guard let lastStroke = self.currentStroke else {
                owsFailDebug("Missing last stroke.")
                removeCurrentStroke()
                return
            }

            // Model items are immutable; we _replace_ the
            // stroke item rather than modify it.
            let stroke = ImageEditorStrokeItem(itemId: lastStroke.itemId, color: strokeColor, unitSamples: currentStrokeSamples, unitStrokeWidth: unitStrokeWidth)
            model.replace(item: stroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                currentStroke = nil
                currentStrokeSamples.removeAll()
            } else {
                currentStroke = stroke
            }
        default:
            removeCurrentStroke()
        }
    }
}

// MARK: -

extension ImageEditorBrushViewController: ImageEditorModelObserver {

    public func imageEditorModelDidChange(before: ImageEditorContents,
                                          after: ImageEditorContents) {
        updateNavigationBar()
    }

    public func imageEditorModelDidChange(changedItemIds: [String]) {
        updateNavigationBar()
    }
}

// MARK: -

extension ImageEditorBrushViewController: ImageEditorPaletteViewDelegate {
    public func selectedColorDidChange() {
        // TODO:
    }
}

// MARK: -

extension ImageEditorBrushViewController: UIGestureRecognizerDelegate {
    @objc public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ignore touches that begin inside the palette.
        let location = touch.location(in: paletteView)
        return !paletteView.bounds.contains(location)
    }
}
