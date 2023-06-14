//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// A table view cell that presents a context menu when tapped.
class ContextMenuPresentingTableViewCell: UITableViewCell {
    private let contextMenuButton: ContextMenuButton

    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap))

    init(contextMenuButton: ContextMenuButton) {
        self.contextMenuButton = contextMenuButton

        super.init(style: .default, reuseIdentifier: nil)

        addGestureRecognizer(tapRecognizer)
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented!")
    }

    @objc
    private func didTap() {
        contextMenuButton.showContextMenu()
    }
}
