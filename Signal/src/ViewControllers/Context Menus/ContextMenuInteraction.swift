//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ContextMenuInteractionDelegate: AnyObject {
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration?
    func contextMenuInteraction(_ interaction: ContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview?
}

class ContextMenuInteraction : NSObject, UIInteraction {
    public var view: UIView?
    
    public func willMove(to view: UIView?) {
        // Manage gesture recognizer state here
    }
    
    public func didMove(to view: UIView?) {
        self.view = view
        // Manage gesture recognizer state here
    }
    
    weak var delegate: ContextMenuInteractionDelegate?
    
    public init(delegate: ContextMenuInteractionDelegate) {
        self.delegate = delegate
    }
    
    // On long press event, request configurationForMenuAtLocation: and previewForHighlightingMenuWithConfiguration
    // If valid, haptic and present view
    
    public func dismissMenu() {
        
    }
}
