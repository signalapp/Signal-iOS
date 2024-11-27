//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import LibSignalClient
import SignalServiceKit

// MARK: - CallLinkApprovalRequestDetailsSheet

class CallLinkApprovalRequestDetailsSheet: OWSTableSheetViewController {

    private struct Deps {
        let contactsManager: any ContactManager
        let db: any DB
    }

    private let deps = Deps(
        contactsManager: SSKEnvironment.shared.contactManagerRef,
        db: DependenciesBridge.shared.db
    )

    let approvalRequest: CallLinkApprovalRequest
    let approvalViewModel: CallLinkApprovalViewModel

    override var handleBackgroundColor: UIColor {
        UIColor.Signal.transparentSeparator
    }

    init(
        approvalRequest: CallLinkApprovalRequest,
        approvalViewModel: CallLinkApprovalViewModel
    ) {
        self.approvalRequest = approvalRequest
        self.approvalViewModel = approvalViewModel
        super.init()

        self.overrideUserInterfaceStyle = .dark
        self.tableViewController.forceDarkMode = true
    }

    private weak var fromViewController: UIViewController?

    func present(
        from viewController: UIViewController,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil,
        animated: Bool = true
    ) {
        self.fromViewController = viewController
        self.dismissalDelegate = dismissalDelegate
        viewController.present(self, animated: animated)
    }

    // MARK: Table contents

    override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()

        contents.add(.init(
            items: [
                // TODO: It would be nice to eventually make OWSTableItem's default values not dependent on Theme and instead use dynamic colors
                .item(
                    icon: .checkCircle,
                    tintColor: UIColor.Signal.label,
                    name: OWSLocalizedString(
                        "CALL_LINK_JOIN_REQUEST_APPROVE_BUTTON",
                        comment: "Button on an action sheet to approve a request to join a call link."
                    ),
                    textColor: UIColor.Signal.label
                ) { [weak self] in
                    guard let self else { return }
                    self.dismiss(animated: true)
                    self.approvalViewModel.performRequestAction.send((.approve, self.approvalRequest))
                },
                .item(
                    icon: .xCircle,
                    tintColor: UIColor.Signal.label,
                    name: OWSLocalizedString(
                        "CALL_LINK_JOIN_REQUEST_DENY_BUTTON",
                        comment: "Button on an action sheet to deny a request to join a call link."
                    ),
                    textColor: UIColor.Signal.label
                ) { [weak self] in
                    guard let self else { return }
                    self.dismiss(animated: true)
                    self.approvalViewModel.performRequestAction.send((.deny, self.approvalRequest))
                },
            ],
            headerView: self.buildHeader()
        ))

        tableViewController.setContents(contents, shouldReload: shouldReload)
    }

    // MARK: Header

    private func buildHeader() -> UIView {
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 8
        vStack.alignment = .center
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.layoutMargins = .init(
            top: 20,
            left: tableViewController.cellHOuterLeftMargin,
            bottom: 36,
            right: tableViewController.cellHOuterRightMargin
        )

        // [CallLink] TODO: This should expand to a full-screen preview when tapped
        let avatarView = ConversationAvatarView(
            sizeClass: .eightyEight,
            localUserDisplayMode: .asLocalUser,
            badged: true
        )

        let (contactTitle, mutualThreads): (NSAttributedString, [TSGroupThread]) = self.deps.db.read { tx in
            avatarView.update(SDSDB.shimOnlyBridge(tx)) { config in
                config.dataSource = .address(self.approvalRequest.address)
            }

            let isSystemContact = self.deps.contactsManager.fetchSignalAccount(
                for: self.approvalRequest.address,
                transaction: SDSDB.shimOnlyBridge(tx)
            ) != nil

            let mutualThreads = TSGroupThread.groupThreads(
                with: self.approvalRequest.address,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            .filter(\.isLocalUserFullMember)
            .filter(\.shouldThreadBeVisible)

            let contactTitle = ConversationHeaderBuilder.threadAttributedString(
                threadName: self.approvalRequest.name,
                isNoteToSelf: false,
                isSystemContact: isSystemContact,
                canTap: true,
                tx: SDSDB.shimOnlyBridge(tx)
            )

            return (contactTitle, mutualThreads)
        }

        vStack.addArrangedSubview(avatarView)

        let nameButton = OWSButton { [weak self] in
            self?.didTapName()
        }
        nameButton.dimsWhenHighlighted = true
        nameButton.titleLabel?.numberOfLines = 0
        nameButton.titleLabel?.textAlignment = .center
        nameButton.setAttributedTitle(contactTitle, for: .normal)
        vStack.addArrangedSubview(nameButton)

        let mutualGroupsLabel = UILabel()
        mutualGroupsLabel.text = ProfileDetailLabel.mutualGroupsString(isInGroupContext: false, mutualGroups: mutualThreads)
        mutualGroupsLabel.font = .dynamicTypeBody2
        mutualGroupsLabel.textColor = UIColor.Signal.secondaryLabel

        vStack.addArrangedSubview(mutualGroupsLabel)

        return vStack
    }

    private func didTapName() {
        guard let fromViewController else {
            owsFailDebug("Parent view controller missing")
            return
        }
        let thread = TSContactThread.getOrCreateThread(contactAddress: approvalRequest.address)
        let sheet = ContactAboutSheet(thread: thread, spoilerState: .init())
        sheet.overrideUserInterfaceStyle = .dark
        self.dismiss(animated: true) {
            sheet.present(from: fromViewController, dismissalDelegate: self.dismissalDelegate)
        }
    }
}

// MARK: - Previews

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    SheetPreviewViewController { viewController, animated in
        CallLinkApprovalRequestDetailsSheet(
            approvalRequest: .init(aci: .init(fromUUID: UUID()), name: "Candice"),
            approvalViewModel: CallLinkApprovalViewModel()
        )
        .present(from: viewController, animated: animated)
    }
}
#endif
