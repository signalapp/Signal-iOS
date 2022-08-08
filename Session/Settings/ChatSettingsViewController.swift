// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SignalUtilitiesKit

// FIXME: Refactor to be MVVM and use database observation
class ChatSettingsViewController: OWSTableViewController {
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.updateTableContents()
        
        ViewControllerUtilities.setUpDefaultSessionStyle(for: self, title: "CHATS_TITLE".localized(), hasCustomBackButton: false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.updateTableContents()
    }
    
    // MARK: - Table Contents
    
    func updateTableContents() {
        let updatedContents: OWSTableContents = OWSTableContents()
        
        let messageTrimming: OWSTableSection = OWSTableSection()
        messageTrimming.headerTitle = "MESSAGE_TRIMMING_TITLE".localized()
        messageTrimming.footerTitle = "MESSAGE_TRIMMING_OPEN_GROUP_DESCRIPTION".localized()
        messageTrimming.add(OWSTableItem.switch(
            withText: "MESSAGE_TRIMMING_OPEN_GROUP_TITLE".localized(),
            isOn: { Storage.shared[.trimOpenGroupMessagesOlderThanSixMonths] },
            target: self,
            selector: #selector(didToggleTrimOpenGroupsSwitch(_:))
        ))
        updatedContents.addSection(messageTrimming)
        
        self.contents = updatedContents
    }

    // MARK: - Actions
    
    @objc private func didToggleTrimOpenGroupsSwitch(_ sender: UISwitch) {
        let switchIsOn: Bool = sender.isOn
        
        Storage.shared.writeAsync(
            updates: { db in
                db[.trimOpenGroupMessagesOlderThanSixMonths] = !switchIsOn
            },
            completion: { [weak self] _, _ in
                self?.updateTableContents()
            }
        )
    }
    
    @objc private func close(_ sender: UIBarButtonItem) {
        self.navigationController?.dismiss(animated: true)
    }
}
