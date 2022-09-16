//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol ContextMenuButtonDelegate: AnyObject {

    func contextMenuConfiguration(for contextMenuButton: DelegatingContextMenuButton) -> ContextMenuConfiguration?

    func contextMenuWillDisplay(from contextMenuButton: DelegatingContextMenuButton)
    /// Note: called _after_ action handlers if dismissed by tapping a context menu action.
    func contextMenuDidDismiss(from contextMenuButton: ContextMenuButton)
}

extension ContextMenuButtonDelegate {

    func contextMenuWillDisplay(from contextMenuButton: DelegatingContextMenuButton) {}

    func contextMenuDidDismiss(from contextMenuButton: ContextMenuButton) {}
}

/// This class exists to keep ContextMenuButton as clean and close to iOS 14+ APIs on UIButton as possible.
/// Eventually, we will drop iOS 13 support, get rid of ContextMenuButton, and have this subclass UIButton
/// instead. Hence, it is structured to not get any special access to the internals of ContextMenuButton it
/// wouldn't have if it was an iOS 14+ UIButton instead.
public class DelegatingContextMenuButton: ContextMenuButton {

    public weak var delegate: ContextMenuButtonDelegate?

    public init(delegate: ContextMenuButtonDelegate? = nil) {
        self.delegate = delegate

        // UIButton's native implementation of context menu handling won't show
        // a context menu unless provided one in its `menu` var, or equivalently in
        // its menu initializer. As long as we override the context menu configuration
        // method, it doesn't matter what gets set, as long as something is set.
        // So we set a dummy value.
        super.init(contextMenu: ContextMenu([ContextMenuAction(handler: { _ in })]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> ContextMenuConfiguration? {
        return delegate?.contextMenuConfiguration(for: self)
    }

    public override func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        willDisplayMenuForConfiguration: ContextMenuConfiguration
    ) {
        delegate?.contextMenuWillDisplay(from: self)
    }

    public override func contextMenuInteraction(_ interaction: ContextMenuInteraction, didEndForConfiguration: ContextMenuConfiguration) {
        delegate?.contextMenuDidDismiss(from: self)
    }
}
