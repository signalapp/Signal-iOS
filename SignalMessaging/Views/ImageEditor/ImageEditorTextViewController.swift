//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

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
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(self.modifiedReturnPressed(sender:)), discoverabilityTitle: "Send Message"),
            UIKeyCommand(input: "\r", modifierFlags: .alternate, action: #selector(self.modifiedReturnPressed(sender:)), discoverabilityTitle: "Send Message")
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
public protocol ImageEditorTextViewControllerDelegate: class {
    func textEditDidComplete(textItem: ImageEditorTextItem, text: String?, color: ImageEditorColor)
    func textEditDidCancel()
}

// MARK: -

// A view for editing text item in image editor.
public class ImageEditorTextViewController: OWSViewController, VAlignTextViewDelegate {
    private weak var delegate: ImageEditorTextViewControllerDelegate?

    private let textItem: ImageEditorTextItem

    private let maxTextWidthPoints: CGFloat

    private let textView = VAlignTextView(alignment: .center)

    private let model: ImageEditorModel

    private let canvasView: ImageEditorCanvasView

    private let paletteView: ImageEditorPaletteView

    init(delegate: ImageEditorTextViewControllerDelegate,
         model: ImageEditorModel,
         textItem: ImageEditorTextItem,
         maxTextWidthPoints: CGFloat) {
        self.delegate = delegate
        self.model = model
        self.textItem = textItem
        self.maxTextWidthPoints = maxTextWidthPoints
        self.canvasView = ImageEditorCanvasView(model: model,
                                                itemIdsToIgnore: [textItem.itemId])
        self.paletteView = ImageEditorPaletteView(currentColor: textItem.color)

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
        self.view.backgroundColor = .black
        self.view.isOpaque = true

        canvasView.configureSubviews()
        self.view.addSubview(canvasView)
        canvasView.autoPinEdgesToSuperviewEdges()

        let tintView = UIView()
        tintView.backgroundColor = UIColor(white: 0, alpha: 0.33)
        tintView.isOpaque = false
        self.view.addSubview(tintView)
        tintView.autoPinEdgesToSuperviewEdges()
        tintView.layer.opacity = 0
        UIView.animate(withDuration: 0.25, animations: {
            tintView.layer.opacity = 1
        }, completion: { (_) in
            tintView.layer.opacity = 1
        })

        configureTextView()

        self.view.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        self.view.addSubview(textView)
        textView.autoPinTopToSuperviewMargin()
        textView.autoHCenterInSuperview()
        self.autoPinView(toBottomOfViewControllerOrKeyboard: textView, avoidNotch: true)

        paletteView.delegate = self
        self.view.addSubview(paletteView)
        paletteView.autoAlignAxis(.horizontal, toSameAxisOf: textView)
        paletteView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 20)
        // This will determine the text view's size.
        paletteView.autoPinEdge(.leading, to: .trailing, of: textView, withOffset: 8)

        updateNavigationBar()
    }

    private func configureTextView() {
        textView.text = textItem.text
        textView.font = textItem.font
        textView.textColor = textItem.color.color

        textView.isEditable = true
        textView.backgroundColor = .clear
        textView.isOpaque = false
        // We use a white cursor since we use a dark background.
        textView.tintColor = .white
        textView.returnKeyType = .done
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
        self.delegate?.textEditDidComplete(textItem: textItem, text: textView.text, color: paletteView.selectedValue)

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
        self.textView.textColor = self.paletteView.selectedValue.color
    }
}
