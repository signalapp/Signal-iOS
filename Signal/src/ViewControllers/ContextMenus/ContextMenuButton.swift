//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// A button that shows a fixed context menu when tapped.
class ContextMenuButton: UIButton {
    override var intrinsicContentSize: CGSize { .zero }

    private let onWillDisplayContextMenu: () -> Void
    private let onDidDismissContextMenu: () -> Void

    /// Creates a context menu button with the given actions.
    init(
        actions: [UIMenuElement],
        onWillDisplayContextMenu: @escaping () -> Void = {},
        onDidDismissContextMenu: @escaping () -> Void = {},
    ) {
        self.onWillDisplayContextMenu = onWillDisplayContextMenu
        self.onDidDismissContextMenu = onDidDismissContextMenu
        super.init(frame: .zero)
        setActions(actions: actions)
    }

    /// Creates an empty context menu button. Callers should subsequently call
    /// ``setActions(actions:)`` manually to populate the button.
    init(
        empty: Void,
        onWillDisplayContextMenu: @escaping () -> Void = {},
        onDidDismissContextMenu: @escaping () -> Void = {},
    ) {
        self.onWillDisplayContextMenu = onWillDisplayContextMenu
        self.onDidDismissContextMenu = onDidDismissContextMenu
        super.init(frame: .zero)
        setActions(actions: [])
    }

    /// Set the actions for this button's context menu.
    func setActions(actions: [UIMenuElement]) {
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
        animator: (any UIContextMenuInteractionAnimating)?,
    ) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onWillDisplayContextMenu()
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?,
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onDidDismissContextMenu()
    }
}
