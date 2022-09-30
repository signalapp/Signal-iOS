//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import SessionUIKit

@objc
public protocol VAlignTextViewDelegate: class {
    func textViewDidComplete()
}

// MARK: -

private class VAlignTextView: UITextView {
    fileprivate weak var textViewDelegate: VAlignTextViewDelegate?

    enum Alignment: String {
        case top
        case center
        case bottom
    }
    private let alignment: Alignment

    @objc public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                updateInsets()
            }
        }
    }

    @objc public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                updateInsets()
            }
        }
    }

    public init(alignment: Alignment) {
        self.alignment = alignment

        super.init(frame: .zero, textContainer: nil)

        self.addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    deinit {
        self.removeObserver(self, forKeyPath: "contentSize")
    }

    private func updateInsets() {
        let topOffset: CGFloat
        switch alignment {
        case .top:
            topOffset = 0
        case .center:
            topOffset = max(0, (self.height() - contentSize.height) * 0.5)
        case .bottom:
            topOffset = max(0, self.height() - contentSize.height)
        }
        contentInset = UIEdgeInsets(top: topOffset, leading: 0, bottom: 0, trailing: 0)
    }

    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        updateInsets()
    }

    // MARK: - Key Commands

    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(self.modifiedReturnPressed(sender:)), discoverabilityTitle: "Add Text"),
            UIKeyCommand(input: "\r", modifierFlags: .alternate, action: #selector(self.modifiedReturnPressed(sender:)), discoverabilityTitle: "Add Text")
        ]
    }

    @objc
    public func modifiedReturnPressed(sender: UIKeyCommand) {
        Logger.verbose("")

        self.textViewDelegate?.textViewDidComplete()
    }
}

// MARK: -

@objc
public protocol ImageEditorTextViewControllerDelegate: AnyObject {
    func textEditDidComplete(textItem: ImageEditorTextItem)
    func textEditDidDelete(textItem: ImageEditorTextItem)
    func textEditDidCancel()
}

// MARK: -

// A view for editing text item in image editor.
public class ImageEditorTextViewController: OWSViewController, VAlignTextViewDelegate {
    private weak var delegate: ImageEditorTextViewControllerDelegate?

    private let textItem: ImageEditorTextItem
    private let isNewItem: Bool
    private let maxTextWidthPoints: CGFloat
    private let textView = VAlignTextView(alignment: .center)
    private let model: ImageEditorModel
    private let canvasView: ImageEditorCanvasView
    private let paletteView: ImageEditorPaletteView
    private let bottomInset: CGFloat

    init(
        delegate: ImageEditorTextViewControllerDelegate,
        model: ImageEditorModel,
        textItem: ImageEditorTextItem,
        isNewItem: Bool,
        maxTextWidthPoints: CGFloat,
        bottomInset: CGFloat
    ) {
        self.delegate = delegate
        self.model = model
        self.textItem = textItem
        self.isNewItem = isNewItem
        self.maxTextWidthPoints = maxTextWidthPoints
        self.canvasView = ImageEditorCanvasView(
            model: model,
            itemIdsToIgnore: [textItem.itemId]
        )
        self.paletteView = ImageEditorPaletteView(currentColor: textItem.color)
        self.bottomInset = bottomInset

        super.init(nibName: nil, bundle: nil)

        self.textView.textViewDelegate = self
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - View Lifecycle

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        textView.becomeFirstResponder()

        self.view.layoutSubviews()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textView.becomeFirstResponder()

        self.view.layoutSubviews()
    }

    public override func loadView() {
        self.view = UIView()
        self.view.themeBackgroundColor = .newConversation_background
        self.view.isOpaque = true

        canvasView.configureSubviews()
        self.view.addSubview(canvasView)
        canvasView.pin(.top, to: .top, of: self.view)
        canvasView.pin(.leading, to: .leading, of: self.view)
        canvasView.pin(.trailing, to: .trailing, of: self.view)
        canvasView.pin(.bottom, to: .bottom, of: self.view, withInset: -bottomInset)

        let tintView = UIView()
        tintView.themeBackgroundColor = .black
        tintView.alpha = 0
        self.view.addSubview(tintView)
        
        tintView.autoPinEdgesToSuperviewEdges()
        
        UIView.animate(withDuration: 0.25) {
            tintView.alpha = 0.4
        }

        configureTextView()

        self.view.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        self.view.addSubview(textView)
        textView.autoPinTopToSuperviewMargin()
        textView.autoHCenterInSuperview()
        self.autoPinView(toBottomOfViewControllerOrKeyboard: textView, avoidNotch: true)

        paletteView.delegate = self
        self.view.addSubview(paletteView)
        paletteView.autoAlignAxis(.horizontal, toSameAxisOf: textView)
        paletteView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 0)
        // This will determine the text view's size.
        paletteView.autoPinEdge(.leading, to: .trailing, of: textView, withOffset: 0)

        let pinchGestureRecognizer = ImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pinchGestureRecognizer.referenceView = view
        view.addGestureRecognizer(pinchGestureRecognizer)

        updateNavigationBar()
    }

    private func configureTextView() {
        textView.text = textItem.text
        textView.font = textItem.font
        textView.themeTextColorForced = .color(textItem.color.color)

        textView.isEditable = true
        textView.themeBackgroundColor = .clear
        textView.isOpaque = false
        // We use a white cursor since we use a dark background.
        textView.themeTintColor = .primary
        // TODO: Limit the size of the text?
        // textView.delegate = self
        textView.isScrollEnabled = true
        textView.scrollsToTop = false
        textView.isUserInteractionEnabled = true
        textView.textAlignment = .center
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInset = .zero
    }

    private func updateNavigationBar() {
        let undoButton = navigationBarButton(imageName: "image_editor_undo",
                                             selector: #selector(didTapUndo(sender:)))
        let doneButton = navigationBarButton(imageName: "image_editor_checkmark_full",
                                             selector: #selector(didTapDone(sender:)))

        let navigationBarItems = [undoButton, doneButton]
        updateNavigationBar(navigationBarItems: navigationBarItems)
    }

    @objc
    override public var canBecomeFirstResponder: Bool {
        return true
    }

    // MARK: - Pinch Gesture

    private var pinchFontStart: UIFont?

    @objc
    public func handlePinchGesture(_ gestureRecognizer: ImageEditorPinchGestureRecognizer) {
        AssertIsOnMainThread()

        switch gestureRecognizer.state {
        case .began:
            pinchFontStart = textView.font
        case .changed, .ended:
            guard let pinchFontStart = pinchFontStart else {
                return
            }
            var pointSize: CGFloat = pinchFontStart.pointSize
            if gestureRecognizer.pinchStateLast.distance > 0 {
                pointSize *= gestureRecognizer.pinchStateLast.distance / gestureRecognizer.pinchStateStart.distance
            }
            let minPointSize: CGFloat = 12
            let maxPointSize: CGFloat = 64
            pointSize = max(minPointSize, min(maxPointSize, pointSize))
            let font = pinchFontStart.withSize(pointSize)
            textView.font = font
        default:
            pinchFontStart = nil
        }
    }

    // MARK: - Events

    @objc func didTapUndo(sender: UIButton) {
        Logger.verbose("")

        self.delegate?.textEditDidCancel()

        self.dismiss(animated: false) {
            // Do nothing.
        }
    }

    @objc func didTapDone(sender: UIButton) {
        Logger.verbose("")

        completeAndDismiss()
    }

    private func completeAndDismiss() {
        var newTextItem = textItem

        if isNewItem {
            let view = self.canvasView.gestureReferenceView
            let viewBounds = view.bounds

            // Ensure continuity of the new text item's location
            // with its apparent location in this text editor.
            let locationInView = view.convert(textView.bounds.center, from: textView).clamp(view.bounds)
            let textCenterImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
                                                                              viewBounds: viewBounds,
                                                                              model: model,
                                                                              transform: model.currentTransform())

            // Same, but for size.
            let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewBounds.size,
                                                              imageSize: model.srcImageSizePixels,
                                                              transform: model.currentTransform())
            let unitWidth = textView.width() / imageFrame.width
            newTextItem = textItem.copy(unitCenter: textCenterImageUnit).copy(unitWidth: unitWidth)
        }

        var font = textItem.font
        if let newFont = textView.font {
            font = newFont
        } else {
            owsFailDebug("Missing font.")
        }
        newTextItem = newTextItem.copy(font: font)

        guard let text = textView.text?.ows_stripped(),
            text.count > 0 else {
                self.delegate?.textEditDidDelete(textItem: textItem)

                self.dismiss(animated: false) {
                    // Do nothing.
                }

                return
        }

        newTextItem = newTextItem.copy(withText: text, color: paletteView.selectedValue)

        // Hide the text view immediately to avoid animation glitches in the dismiss transition.
        textView.isHidden = true

        if textItem == newTextItem {
            // No changes were made.  Cancel to avoid dirtying the undo stack.
            self.delegate?.textEditDidCancel()
        } else {
            self.delegate?.textEditDidComplete(textItem: newTextItem)
        }

        self.dismiss(animated: false) {
            // Do nothing.
        }
    }

    // MARK: - VAlignTextViewDelegate

    public func textViewDidComplete() {
        completeAndDismiss()
    }
}

// MARK: -

extension ImageEditorTextViewController: ImageEditorPaletteViewDelegate {
    public func selectedColorDidChange() {
        self.textView.themeTextColorForced = .color(self.paletteView.selectedValue.color)
    }
}
