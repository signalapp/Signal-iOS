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
    let showDebugRects = true

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

                if showDebugRects {
                    view.layer.borderColor = UIColor.red.cgColor
                    view.layer.borderWidth = 1
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

                    if showDebugRects {
                        accessory.accessoryView.layer.borderColor = UIColor.blue.cgColor
                        accessory.accessoryView.layer.borderWidth = 1
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
        accessoryFrame.size = accessory.size

        if accessory.edgeAlignment.contains(.top) {
            accessoryFrame.y = previewFrame.y
        }

        if accessory.edgeAlignment.contains(.trailing) {
            accessoryFrame.x = previewFrame.x - accessoryFrame.size.width
        }

        if accessory.edgeAlignment.contains(.leading) {
            accessoryFrame.x = previewFrame.x + previewFrame.width + accessoryFrame.width
        }

        if accessory.edgeAlignment.contains(.bottom) {
            accessoryFrame.y = previewFrame.y + previewFrame.height - accessoryFrame.height
        }

        accessoryFrame.origin = CGPointAdd(accessoryFrame.origin, accessory.alignmentOffset)

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
        blurView.bounds = view.bounds
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
