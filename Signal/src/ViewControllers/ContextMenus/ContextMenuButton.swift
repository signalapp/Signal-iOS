//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

protocol ContextMenuButtonDelegate: AnyObject {
    /// The context menu for the given button will display.
    func contextMenuWillDisplay(from contextMenuButton: ContextMenuButton)

    /// The context menu for the given button dismissed.
    func contextMenuDidDismiss(from contextMenuButton: ContextMenuButton)
}

/// A button that shows a fixed context menu when tapped.
///
/// - SeeAlso: ``DelegatingContextMenuButton``
class ContextMenuButton: UIButton {
    override var intrinsicContentSize: CGSize { .zero }

    weak var delegate: (any ContextMenuButtonDelegate)?

    /// Creates a context menu button with the given actions.
    init(actions: [UIAction]) {
        super.init(frame: .zero)
        setActions(actions: actions)
    }

    /// Creates an empty context menu button. Callers should subsequently call
    /// ``setActions(actions:)`` manually to populate the button.
    init(empty: Void) {
        super.init(frame: .zero)
        setActions(actions: [])
    }

    /// Set the actions for this button's context menu.
    func setActions(actions: [UIAction]) {
        showsMenuAsPrimaryAction = true
        menu = UIMenu(children: actions)
    }

    @available(*, unavailable, message: "Use other initializer!")
    required init?(coder: NSCoder) {
        owsFail("Use other initializer!")
    }

    // MARK: -

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        delegate?.contextMenuWillDisplay(from: self)
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        delegate?.contextMenuDidDismiss(from: self)
    }
}
