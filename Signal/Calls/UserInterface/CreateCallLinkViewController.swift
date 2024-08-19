//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class CreateCallLinkViewController: InteractiveSheetViewController {
    private let callLink: CallLink
    private let adminPasskey: Data
    private var callLinkState: CallLinkState

    private lazy var _navigationController = OWSNavigationController()
    private lazy var _tableViewController = _CreateCallLinkViewController()

    override var interactiveScrollViews: [UIScrollView] { [self._tableViewController.tableView] }

    override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    // MARK: -

    init(callLink: CallLink, adminPasskey: Data, callLinkState: CallLinkState) {
        self.callLink = callLink
        self.adminPasskey = adminPasskey
        self.callLinkState = callLinkState

        super.init()

        self.allowsExpansion = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self._navigationController.viewControllers = [ self._tableViewController ]
        self.addChild(self._navigationController)
        self._navigationController.didMove(toParent: self)
        self.contentView.addSubview(self._navigationController.view)
        self._navigationController.view.autoPinEdgesToSuperviewEdges()

        updateContents(shouldReload: false)

        self._tableViewController.navigationItem.rightBarButtonItem = .doneButton(
            action: { [unowned self] in
                self.persistIfNeeded()
                self.dismiss(animated: true)
            }
        )
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        self.view.layoutIfNeeded()
        // InteractiveSheetViewController doesn't work with adjustedContentInset.
        self._tableViewController.tableView.contentInsetAdjustmentBehavior = .never
        self._tableViewController.tableView.contentInset = UIEdgeInsets(
            top: self._navigationController.navigationBar.bounds.size.height,
            left: 0,
            bottom: self.view.safeAreaInsets.bottom,
            right: 0
        )

        self.minimizedHeight = (
            self._tableViewController.tableView.contentSize.height
            + self._tableViewController.tableView.contentInset.totalHeight
            + InteractiveSheetViewController.Constants.handleHeight
        )
    }

    // MARK: - Contents

    private func updateContents(shouldReload: Bool) {
        self._tableViewController.setContents(buildTableContents(), shouldReload: shouldReload)
    }

    private func buildTableContents() -> OWSTableContents {
        let linkItem = OWSTableItem.item(name: callLink.url().absoluteString)
        let joinItem = OWSTableItem.actionItem(withText: "Join Call", actionBlock: { [unowned self] in
            GroupCallViewController.presentLobby(for: self.callLink, adminPasskey: self.adminPasskey)
        })

        var settingItems = [OWSTableItem]()
        settingItems.append(.item(
            name: callLinkState.name != nil ? CallStrings.editCallName : CallStrings.addCallName,
            accessoryType: .disclosureIndicator,
            actionBlock: { [unowned self] in self.editName() }
        ))
        settingItems.append(.switch(
            withText: CallStrings.approveAllMembers,
            isOn: { [unowned self] in self.callLinkState.requiresAdminApproval },
            target: self,
            selector: #selector(toggleApproveAllMembers(_:))
        ))

        let sharingSection = OWSTableSection(items: [
            .item(
                icon: .buttonForward,
                name: CallStrings.shareLinkViaSignal,
                actionBlock: { [unowned self] in self.shareCallLinkViaSignal() }
            ),
            .item(
                icon: .buttonCopy,
                name: CallStrings.copyLinkToClipboard,
                actionBlock: { [unowned self] in self.copyCallLink() }
            ),
            OWSTableItem(
                customCellBlock: { self.systemShareTableViewCell },
                actionBlock: { [unowned self] in self.shareCallLinkViaSystem() }
            )
        ])
        sharingSection.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + OWSTableItem.iconSize + OWSTableItem.iconSpacing

        return OWSTableContents(
            title: CallStrings.createCallLinkTitle,
            sections: [
                OWSTableSection(items: [linkItem, joinItem]),
                OWSTableSection(items: settingItems),
                sharingSection,
            ]
        )
    }

    private lazy var systemShareTableViewCell = OWSTableItem.buildCell(
        name: CallStrings.shareLinkViaSystem,
        iconView: OWSTableItem.imageView(forIcon: .buttonShare)
    )

    // MARK: - Actions

    private var didPersist = false
    /// Adds the Call Link to the Calls Tab.
    ///
    /// This should be called after the user makes an "escaping" change to the
    /// Call Link (eg sharing it or copying it) or when they explicitly tap
    /// "Done" to confirm it.
    private func persistIfNeeded() {
        if didPersist {
            return
        }
        // [CallLink] TODO: Insert it into the Calls Tab.
    }

    private func editName() {
        let editNameViewController = EditCallLinkNameViewController(
            oldCallName: self.callLinkState.name ?? "",
            setNewCallName: self.updateName(_:)
        )
        self.presentFormSheet(
            OWSNavigationController(rootViewController: editNameViewController),
            animated: true
        )
    }

    private func updateName(_ name: String) {
        updateCallLink { callLinkManager, authCredential in
            return try await callLinkManager.updateCallLinkName(
                name,
                rootKey: self.callLink.rootKey,
                adminPasskey: self.adminPasskey,
                authCredential: authCredential
            )
        }
    }

    @objc
    private func toggleApproveAllMembers(_ sender: UISwitch) {
        let isOn = sender.isOn
        updateCallLink { callLinkManager, authCredential in
            return try await callLinkManager.updateCallLinkRestrictions(
                requiresAdminApproval: isOn,
                rootKey: self.callLink.rootKey,
                adminPasskey: self.adminPasskey,
                authCredential: authCredential
            )
        }
    }

    private func shareCallLinkViaSignal() {
        owsFail("[CallLink] TODO: Add support for sharing via Signal.")
    }

    private func copyCallLink() {
        self.persistIfNeeded()
        UIPasteboard.general.url = self.callLink.url()
        self.presentToast(text: OWSLocalizedString(
            "COPIED_TO_CLIPBOARD",
            comment: "Indicator that a value has been copied to the clipboard."
        ))
    }

    private func shareCallLinkViaSystem() {
        self.persistIfNeeded()
        let shareViewController = UIActivityViewController(
            activityItems: [self.callLink.url()],
            applicationActivities: nil
        )
        shareViewController.popoverPresentationController?.sourceView = self.systemShareTableViewCell
        self.present(shareViewController, animated: true)
    }

    // MARK: - Create & Present

    static func createCallLinkOnServerAndPresent(from viewController: UIViewController) {
        ModalActivityIndicatorViewController.present(
            fromViewController: viewController,
            presentationDelay: 0.25,
            asyncBlock: { modal in
                do {
                    let callLink = CallLink.generate()
                    let callService = AppEnvironment.shared.callService!
                    let createResult = try await callService.callLinkManager.createCallLink(rootKey: callLink.rootKey)
                    modal.dismissIfNotCanceled {
                        viewController.present(CreateCallLinkViewController(
                            callLink: callLink,
                            adminPasskey: createResult.adminPasskey,
                            callLinkState: createResult.callLinkState
                        ), animated: true)
                    }
                } catch {
                    modal.dismissIfNotCanceled {
                        // [CallLink] TODO: Present these errors to the user.
                        Logger.warn("\(error)")
                    }
                }
            }
        )
    }

    // MARK: - Update Call Link

    private var priorTask: Task<Void, Never>?
    private func updateCallLink(_ performUpdate: @escaping (_ callLinkManager: CallLinkManager, _ authCredential: SignalServiceKit.CallLinkAuthCredential) async throws -> CallLinkState) {
        let priorTask = self.priorTask
        self.priorTask = Task {
            await priorTask?.value
            await self._updateCallLink(performUpdate)
        }
    }

    private func _updateCallLink(_ performUpdate: (CallLinkManager, SignalServiceKit.CallLinkAuthCredential) async throws -> CallLinkState) async {
        let authCredentialManager = AppEnvironment.shared.callService.authCredentialManager
        let callLinkManager = AppEnvironment.shared.callService.callLinkManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        do {
            let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
            let authCredential = try await authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
            self.callLinkState = try await performUpdate(callLinkManager, authCredential)
            updateContents(shouldReload: true)
        } catch {
            Logger.warn("[CallLink] TODO: Couldn't update Call Link: \(error)")
        }
    }
}

// MARK: -

private class _CreateCallLinkViewController: OWSTableViewController2 {
    override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    override var navbarBackgroundColorOverride: UIColor? { tableBackgroundColor }
}
