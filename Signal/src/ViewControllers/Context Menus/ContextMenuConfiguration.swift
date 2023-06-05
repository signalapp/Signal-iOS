//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public typealias ContextMenuActionHandler = (ContextMenuAction) -> Void

// UIAction analog
public class ContextMenuAction {

    public struct Attributes: OptionSet {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let disabled = ContextMenuAction.Attributes(rawValue: 1 << 0)
        public static let destructive = ContextMenuAction.Attributes(rawValue: 1 << 1)
    }

    public let title: String
    public let image: UIImage?
    public let attributes: Attributes

    public let handler: ContextMenuActionHandler

    public init (
        title: String = "",
        image: UIImage? = nil,
        attributes: ContextMenuAction.Attributes = [],
        handler: @escaping ContextMenuActionHandler
    ) {
        self.title = title
        self.image = image
        self.attributes = attributes
        self.handler = handler
    }

}

/// UIMenu analog, supports single depth menus only
public class ContextMenu {
    public let children: [ContextMenuAction]

    public init(
        _ children: [ContextMenuAction]
    ) {
        self.children = children
    }
}

protocol ContextMenuTargetedPreviewAccessoryInteractionDelegate: AnyObject {
    func contextMenuTargetedPreviewAccessoryRequestsDismissal(_ accessory: ContextMenuTargetedPreviewAccessory, completion: @escaping () -> Void)
    func contextMenuTargetedPreviewAccessoryPreviewAlignment(_ accessory: ContextMenuTargetedPreviewAccessory) -> ContextMenuTargetedPreview.Alignment
    func contextMenuTargetedPreviewAccessoryRequestsEmojiPicker(_ accessory: ContextMenuTargetedPreviewAccessory, completion: @escaping (String) -> Void)
}

/// Encapsulates an accessory view with relevant layout information
public class ContextMenuTargetedPreviewAccessory {

    public struct AccessoryAlignment {
        public enum Edge {
            case top
            case trailing
            case leading
            case bottom
        }

        public enum Origin {
            case interior
            case exterior
        }

        /// Accessory frame edge alignment relative to preview frame.
        /// Processed in-order
        let alignments: [(Edge, Origin)]
        let alignmentOffset: CGPoint
    }

    /// Accessory view
    var accessoryView: UIView

    // Defines accessory layout relative to preview view
    var accessoryAlignment: AccessoryAlignment
    var landscapeAccessoryAlignment: AccessoryAlignment?

    var animateAccessoryPresentationAlongsidePreview: Bool = false
    var targetAnimateOutFrame: CGRect?

    weak var delegate: ContextMenuTargetedPreviewAccessoryInteractionDelegate?

    init(
        accessoryView: UIView,
        accessoryAlignment: AccessoryAlignment
    ) {
        self.accessoryView = accessoryView
        self.accessoryAlignment = accessoryAlignment
    }

    func animateIn(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void
    ) {
        completion()
    }

    func animateOut(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void
    ) {
        completion()
    }

    /// Called when a current touch event changed location
    /// - Parameter locationInView: location relative to accessoryView's coordinate space
    func touchLocationInViewDidChange(locationInView: CGPoint) {

    }
    /// Called when a current touch event ended
    /// - Parameter locationInView: location relative to accessoryView's coordinate space
    /// - Returns: true if accessory handled the touch ending, false if the touch is not relevant to this view
    func touchLocationInViewDidEnd(locationInView: CGPoint) -> Bool {
        return false
    }
}

// UITargetedPreview analog
// Supports snapshotting from target view only, and animating to/from the same target position
// View must be in a window when ContextMenuTargetedPreview is initialized
public class ContextMenuTargetedPreview {

    public enum Alignment {
        case left
        case center
        case right

        public static var leading: Alignment {
            CurrentAppContext().isRTL ? .right : .left
        }

        public static var trailing: Alignment {
            CurrentAppContext().isRTL ? .left : .right
        }
    }

    public let view: UIView
    public var auxiliaryView: UIView? {
        didSet {
            if let auxView = auxiliaryView {
                if let snapshot = auxView.snapshotView(afterScreenUpdates: false) {
                    self.auxiliarySnapshot = snapshot
                }
            }
        }
    }
    public let previewView: UIView
    public let previewViewSourceFrame: CGRect
    public var auxiliarySnapshot: UIView?
    public let alignment: Alignment
    public var alignmentOffset: CGPoint?
    public let accessoryViews: [ContextMenuTargetedPreviewAccessory]

    /// Default targeted preview initializer
    /// View must be in a window
    /// - Parameters:
    ///   - view: View to render preview of
    ///   - alignment: If preview needs to be scaled, this property defines the edge alignment
    ///    in the source view to pin the preview to
    ///   - accessoryViews: accessory view
    public convenience init?(
        view: UIView,
        alignment: Alignment,
        accessoryViews: [ContextMenuTargetedPreviewAccessory]?
    ) {
        AssertIsOnMainThread()
        owsAssertDebug(view.window != nil, "View must be in a window")
        guard let snapshot = view.snapshotView(afterScreenUpdates: false) else {
            owsFailDebug("Unable to snapshot context menu preview view")
            return nil
        }

        self.init(
            view: view,
            previewView: snapshot,
            previewViewSourceFrame: view.frame,
            alignment: alignment,
            accessoryViews: accessoryViews ?? []
        )
    }

    /// Initialize using a custom preview view that may or may not originate from `view`
    /// - Parameters:
    ///   - view: View to render a preview from
    ///   - previewView: The preview to render, this should be an unowned view that does not live an any hierarchies.
    ///   - previewViewSourceFrame: The frame to use as an initial and final rendering point for the `previewView`. This should be in the same coordinate space as `view`. If not provided the frame of `previewView` is used.
    ///   - alignment: If preview needs to be scaled, this property defines the edge alignment
    ///    in the source view to pin the preview to
    ///   - accessoryViews: accessory view
    public required init(
        view: UIView,
        previewView: UIView,
        previewViewSourceFrame: CGRect? = nil,
        alignment: Alignment,
        accessoryViews: [ContextMenuTargetedPreviewAccessory]
    ) {
        self.view = view
        self.previewView = previewView
        self.previewViewSourceFrame = previewViewSourceFrame ?? previewView.frame
        self.alignment = alignment
        self.accessoryViews = accessoryViews
    }
}

public typealias ContextMenuActionProvider = ([ContextMenuAction]) -> ContextMenu?

// UIContextMenuConfiguration analog
public class ContextMenuConfiguration {
    public let identifier: NSCopying
    public let actionProvider: ContextMenuActionProvider?
    public let forceDarkTheme: Bool

    public init (
        identifier: NSCopying?,
        forceDarkTheme: Bool = false,
        actionProvider: ContextMenuActionProvider?
    ) {
        if let ident = identifier {
            self.identifier = ident
        } else {
            self.identifier = UUID() as NSCopying
        }

        self.forceDarkTheme = forceDarkTheme
        self.actionProvider = actionProvider
    }
}
