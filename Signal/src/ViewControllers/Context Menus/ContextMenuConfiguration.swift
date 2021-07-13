//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

typealias ContextMenuActionHandler = (ContextMenuAction) -> Void

//UIAction analog
class ContextMenuAction {

    public struct Attributes : OptionSet {
        public let rawValue: UInt
        
        public static let disabled = ContextMenuAction.Attributes(rawValue: 1 << 0)
        public static let destructive = ContextMenuAction.Attributes(rawValue: 1 << 1)
        public static let hidden = ContextMenuAction.Attributes(rawValue: 1 << 2)
    }
    
    public let title: String
    public let image: UIImage?
    public let attributes: Attributes

    private let handler: ContextMenuActionHandler
    
    public init(
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

//UIMenu analog
//Supports single depth menus only
class ContextMenu {
    public let children: [ContextMenuAction] = []
}

//UITargetedPreview analog
//Supports snapshotting from target view only, and animating to/from the same target position
//View must be in a window when ContextMenuTargetedPreview is initialized

class ContextMenuTargetedPreview {
    
    public struct ContextMenuTargetedPreviewAccessory {
        enum Alignment {
            case top
            case trailing
            case leading
            case bottom
        }
        
        var alignment: Alignment
        var accessoryView: UIView
    }
    
    public let view: UIView
    private let previewFrame: CGRect
    private let snapshot: UIView?
    public let accessoryViews: [ContextMenuTargetedPreviewAccessory]
    
    public init(view: UIView, accessoryViews: [ContextMenuTargetedPreviewAccessory]?) {
        AssertIsOnMainThread()
        owsAssertDebug(view.window != nil, "View must be in a window")
        self.view = view
        
        if let snapshot = view.snapshotView(afterScreenUpdates: false) {
            self.snapshot = snapshot
        } else {
            self.snapshot = nil
            owsFailDebug("Unable to snapshot context menu preview view")
        }
        
        self.accessoryViews = accessoryViews ?? []
        
        //Generate and convert frame from view's superview
        self.previewFrame = CGRect.zero
    }
}

typealias ContextMenuActionProvider = ([ContextMenuAction]) -> ContextMenu?

//UIContextMenuConfiguration analog
class ContextMenuConfiguration {
    public let identifier: NSCopying
    private let actionProvider: ContextMenuActionProvider?
    
    public init(identifier: NSCopying?, actionProvider: ContextMenuActionProvider?) {
        if let ident = identifier {
            self.identifier = ident
        } else {
            self.identifier = NSUUID()
        }
        
        self.actionProvider = actionProvider
    }
}
