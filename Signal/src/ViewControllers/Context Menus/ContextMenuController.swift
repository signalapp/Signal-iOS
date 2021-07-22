//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ContextMenuControllerDelegate: AnyObject {
    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController)
}

protocol ContextMenuViewDelegate: AnyObject {
    func contextMenuViewPreviewSourceFrame(_ contextMenuView: ContextMenuHostView) -> CGRect
}

class ContextMenuHostView: UIView {

    weak var delegate: ContextMenuViewDelegate?

    var blurView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let view = blurView {
                addSubview(view)
            }
        }
    }

    var previewView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let view = previewView {
                addSubview(view)

                if DebugFlags.showContextMenuDebugRects {
                    view.addBorder(with: UIColor.blue)
                }
            }
        }
    }

    var accessoryViews: [ContextMenuTargetedPreviewAccessory]? {
        didSet {
            if let oldAccessoryViews = oldValue {
                for oldAccessory in oldAccessoryViews {
                    oldAccessory.accessoryView.removeFromSuperview()
                }
            }

            if let newAccessoryViews = accessoryViews {
                for accessory in newAccessoryViews {
                    addSubview(accessory.accessoryView)

                    if DebugFlags.showContextMenuDebugRects {
                        accessory.accessoryView.addRedBorder()
                    }
                }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView?.frame = bounds
        if let previewView = self.previewView {
            let previewFrame = delegate?.contextMenuViewPreviewSourceFrame(self) ?? CGRect.zero
            previewView.frame = previewFrame
        }

        if let accessories = accessoryViews {
            for accessory in accessories {
                layoutAccessoryView(accessory: accessory)
            }
        }
    }

    private func layoutAccessoryView(accessory: ContextMenuTargetedPreviewAccessory) {
        guard let previewFrame = previewView?.frame else {
            owsFailDebug("Cannot layout accessory views without a preview view")
            return
        }

        var accessoryFrame = CGRect.zero
        accessory.accessoryView.sizeToFit()
        accessoryFrame.size = accessory.accessoryView.frame.size

        for (edgeAlignment, originAlignment) in accessory.accessoryAlignment.alignments {
            switch (edgeAlignment, originAlignment) {
            case (.top, .exterior):
                accessoryFrame.y = previewFrame.y - accessoryFrame.height
            case (.top, .interior):
                accessoryFrame.y = previewFrame.y
            case (.trailing, .exterior):
                accessoryFrame.x = previewFrame.x + previewFrame.width
            case (.trailing, .interior):
                accessoryFrame.x = previewFrame.x + previewFrame.width  - accessoryFrame.width
            case (.leading, .exterior):
                accessoryFrame.x = previewFrame.x - accessoryFrame.width
            case (.leading, .interior):
                accessoryFrame.x = previewFrame.x
            case (.bottom, .exterior):
                accessoryFrame.y = previewFrame.y + previewFrame.height
            case (.bottom, .interior):
                accessoryFrame.y = previewFrame.y + previewFrame.height - accessoryFrame.height
            }
        }

        accessoryFrame.origin = CGPointAdd(accessoryFrame.origin, accessory.accessoryAlignment.alignmentOffset)

        accessory.accessoryView.frame = accessoryFrame
    }
}

class ContextMenuController: UIViewController, ContextMenuViewDelegate {
    weak var delegate: ContextMenuControllerDelegate?

    let contextMenuPreview: ContextMenuTargetedPreview
    let contextMenuConfiguration: ContextMenuConfiguration // Do we want this or a UIMenu

    lazy var blurView: UIVisualEffectView = {
        let effect = UIBlurEffect(style: UIBlurEffect.Style.regular)
        return UIVisualEffectView(effect: effect)
    }()

    private var emojiPickerSheet: EmojiPickerSheet?

    init (
        configuration: ContextMenuConfiguration, preview: ContextMenuTargetedPreview
    ) {
        self.contextMenuConfiguration = configuration
        self.contextMenuPreview = preview

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIViewController

    override func loadView() {
        let contextMenuView = ContextMenuHostView(frame: CGRect.zero)
        contextMenuView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contextMenuView.delegate = self
        view = contextMenuView

        contextMenuView.blurView = blurView
        contextMenuView.previewView = contextMenuPreview.snapshot
        contextMenuView.accessoryViews = contextMenuPreview.accessoryViews

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapGestureRecogznied(sender:)))
        view.addGestureRecognizer(tapGesture)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        blurView.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        for accessory in contextMenuPreview.accessoryViews {
            accessory.animateIn(duration: 0.2) { }
        }
    }

    // MARK: Public

    public func showEmojiSheet(completion: @escaping (String) -> Void) {
        let picker = EmojiPickerSheet { [weak self] emoji in
            guard let self = self else { return }

            guard let emojiString = emoji?.rawValue else {
                self.delegate?.contextMenuControllerRequestsDismissal(self)
                return
            }

            completion(emojiString)
        }
        picker.externalBackdropView = blurView
        emojiPickerSheet = picker
        present(picker, animated: true)
    }

    public func dismissEmojiSheet(animated: Bool, completion: @escaping () -> Void) {
        emojiPickerSheet?.dismiss(animated: true, completion: completion)
    }

    // MARK: ContextMenuViewDelegate

    func contextMenuViewPreviewSourceFrame(_ contextMenuView: ContextMenuHostView) -> CGRect {
        guard let sourceView = contextMenuPreview.view else {
            owsFailDebug("Expected source view")
            return CGRect.zero
        }
        return view.convert(sourceView.frame, from: sourceView)
    }

    // MARK: Private

    @objc
    private func tapGestureRecogznied(sender: UIGestureRecognizer) {
        delegate?.contextMenuControllerRequestsDismissal(self)
    }
}
