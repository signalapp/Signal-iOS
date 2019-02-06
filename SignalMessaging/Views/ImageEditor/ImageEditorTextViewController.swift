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
    func textEditDidComplete(textItem: ImageEditorTextItem, text: String?)
    func textEditDidCancel()
}

// MARK: -

// A view for editing text item in image editor.
class ImageEditorTextViewController: OWSViewController, VAlignTextViewDelegate {
    private weak var delegate: ImageEditorTextViewControllerDelegate?

    private let textItem: ImageEditorTextItem

    private let maxTextWidthPoints: CGFloat

    private let textView = VAlignTextView(alignment: .bottom)

    init(delegate: ImageEditorTextViewControllerDelegate,
         textItem: ImageEditorTextItem,
         maxTextWidthPoints: CGFloat) {
        self.delegate = delegate
        self.textItem = textItem
        self.maxTextWidthPoints = maxTextWidthPoints

        super.init(nibName: nil, bundle: nil)

        self.textView.textViewDelegate = self
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - View Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        textView.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textView.becomeFirstResponder()
    }

    override func loadView() {
        self.view = UIView()
        self.view.backgroundColor = UIColor(white: 0.5, alpha: 0.5)

        configureTextView()

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop,
                                                           target: self,
                                                           action: #selector(didTapBackButton))

        self.view.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        self.view.addSubview(textView)
        textView.autoPinTopToSuperviewMargin()
        textView.autoHCenterInSuperview()
        // In order to having text wrapping be as WYSIWYG as possible, we limit the text view
        // to the max text width on the image.
        let maxTextWidthPoints = max(self.maxTextWidthPoints, 200)
        textView.autoSetDimension(.width, toSize: maxTextWidthPoints, relation: .lessThanOrEqual)
        self.autoPinView(toBottomOfViewControllerOrKeyboard: textView, avoidNotch: true)
    }

    private func configureTextView() {
        textView.text = textItem.text
        textView.font = textItem.font
        textView.textColor = textItem.color

        textView.isEditable = true
        textView.backgroundColor = .clear
        textView.isOpaque = false
        // We use a white cursor since we use a dark background.
        textView.tintColor = .white
        textView.returnKeyType = .done
        // TODO:
        //        textView.delegate = self
        textView.isScrollEnabled = true
        textView.scrollsToTop = false
        textView.isUserInteractionEnabled = true
        textView.textAlignment = .center
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInset = .zero
    }

    // MARK: - Events

    @objc public func didTapBackButton() {
        completeAndDismiss()
    }

    private func completeAndDismiss() {

        // Before we take a screenshot, make sure selection state
        // auto-complete suggestions, cursor don't affect screenshot.
        textView.resignFirstResponder()
        if textView.isFirstResponder {
            owsFailDebug("Text view is still first responder.")
        }
        textView.selectedTextRange = nil

        self.delegate?.textEditDidComplete(textItem: textItem, text: textView.text)

        self.dismiss(animated: true) {
            // Do nothing.
        }
    }

    // MARK: - VAlignTextViewDelegate

    func textViewDidComplete() {
        completeAndDismiss()
    }
}
