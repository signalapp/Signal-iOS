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

    private func callLinkCardCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let view = CallLinkCardView(
            callLink: self.callLink,
            callLinkState: self.callLinkState,
            joinAction: { [unowned self] in self.joinCall() }
        )
        cell.contentView.addSubview(view)
        view.autoPinLeadingToSuperviewMargin()
        view.autoPinTrailingToSuperviewMargin()
        view.autoPinEdge(.top, to: .top, of: cell.contentView, withOffset: Constants.vMarginCallLinkCard)
        view.autoPinEdge(.bottom, to: .bottom, of: cell.contentView, withOffset: -Constants.vMarginCallLinkCard)

        cell.selectionStyle = .none
        return cell
    }

    private enum Constants {
        static let vMarginCallLinkCard: CGFloat = 12
    }

    private func buildTableContents() -> OWSTableContents {
        let callLinkCardItem = OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                return self.callLinkCardCell()
            }
        )

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
                customCellBlock: {
                    let cell = OWSTableItem.buildCell(
                        icon: .buttonShare,
                        itemName: CallStrings.shareLinkViaSystem
                    )
                    self.systemShareTableViewCell = cell
                    return cell
                },
                actionBlock: { [unowned self] in self.shareCallLinkViaSystem() }
            )
        ])
        sharingSection.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + OWSTableItem.iconSize + OWSTableItem.iconSpacing

        return OWSTableContents(
            title: CallStrings.createCallLinkTitle,
            sections: [
                OWSTableSection(items: [callLinkCardItem]),
                OWSTableSection(items: settingItems),
                sharingSection,
            ]
        )
    }

    private var systemShareTableViewCell: UITableViewCell?

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
        didPersist = true
        createCallLinkRecord()
    }

    private func createCallLinkRecord() {
        // [CallLink] TODO: Make this asynchronous if needed.
        let callLinkStore = DependenciesBridge.shared.callLinkStore
        databaseStorage.write { tx in
            if FeatureFlags.callLinkRecordTable {
                do {
                    var callLinkRecord = try callLinkStore.fetchOrInsert(rootKey: callLink.rootKey, tx: tx.asV2Write)
                    callLinkRecord.adminPasskey = adminPasskey
                    callLinkRecord.updateState(callLinkState)
                    try callLinkStore.update(callLinkRecord, tx: tx.asV2Write)
                } catch {
                    owsFailDebug("Couldn't create CallLinkRecord: \(error)")
                }
            }

            // [CallLink] TODO: Move this into a -Manager object.
            let localThread = TSContactThread.getOrCreateLocalThread(transaction: tx)!
            let callLinkUpdate = OutgoingCallLinkUpdateMessage(
                localThread: localThread,
                rootKey: callLink.rootKey,
                adminPasskey: adminPasskey,
                tx: tx
            )
            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef
            messageSenderJobQueue.add(message: .preprepared(transientMessageWithoutAttachments: callLinkUpdate), transaction: tx)
        }
        storageServiceManager.recordPendingUpdates(callLinkRootKeys: [callLink.rootKey])
    }

    private func joinCall() {
        persistIfNeeded()
        GroupCallViewController.presentLobby(
            for: callLink,
            adminPasskey: adminPasskey,
            // Because the local user is the admin and all the changes
            // they are making to the state are being updated in the
            // local model, we don't need to re-fetch the state from
            // the server. In fact, it feels strange to block the UI with
            // an activity indicator when waiting for this, as we
            // already have all the info necessary to show the call UI.
            callLinkStateRetrievalStrategy: .reuse(callLinkState)
        )
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

    private func updateName(_ name: String) async throws {
        try await updateCallLink(
            { callLinkManager, authCredential in
                return try await callLinkManager.updateCallLinkName(
                    name,
                    rootKey: self.callLink.rootKey,
                    adminPasskey: self.adminPasskey,
                    authCredential: authCredential
                )
            }
        )
    }

    @objc
    private func toggleApproveAllMembers(_ sender: UISwitch) {
        let isOn = sender.isOn
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            presentationDelay: 0.25,
            asyncBlock: { [weak self] modal in
                guard let self else { return }
                let updateResult = await Result { [weak self] in
                    guard let self else { return }
                    try await self.updateCallLink { callLinkManager, authCredential in
                        return try await callLinkManager.updateCallLinkRestrictions(
                            requiresAdminApproval: isOn,
                            rootKey: self.callLink.rootKey,
                            adminPasskey: self.adminPasskey,
                            authCredential: authCredential
                        )
                    }
                }
                modal.dismissIfNotCanceled {
                    do {
                        _ = try updateResult.get()
                    } catch {
                        if error.isNetworkFailureOrTimeout {
                            // [CallLink] TODO: Refresh switch UI, as we don't know whether the operation succeeded or failed.
                        } else {
                            Logger.warn("Call link approve members switch update failed with error \(error)")
                            // The operation definitely failed. Revert switch state.
                            sender.isOn = !isOn
                            OWSActionSheets.showActionSheet(
                                title: CallStrings.callLinkErrorSheetTitle,
                                message: CallStrings.callLinkUpdateErrorSheetDescription
                            )
                        }
                    }
                }
            }
        )
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
                    Logger.warn("Call link creation failed with error \(error)")
                    modal.dismissIfNotCanceled {
                        OWSActionSheets.showActionSheet(
                            title: CallStrings.callLinkErrorSheetTitle,
                            message: OWSLocalizedString(
                                "CALL_LINK_CREATION_FAILURE_SHEET_DESCRIPTION",
                                comment: "Description of sheet presented when call link creation fails."
                            )
                        )
                    }
                }
            }
        )
    }

    // MARK: - Update Call Link

    private var priorTask: Task<Void, any Error>?
    private func updateCallLink(
        _ performUpdate: @escaping (_ callLinkManager: CallLinkManager, _ authCredential: SignalServiceKit.CallLinkAuthCredential) async throws -> CallLinkState
    ) async throws {
        let priorTask = self.priorTask
        let newTask = Task {
            try? await priorTask?.value
            return try await self._updateCallLink(performUpdate)
        }
        self.priorTask = newTask
        return try await newTask.value
    }

    private func _updateCallLink(
        _ performUpdate: (CallLinkManager, SignalServiceKit.CallLinkAuthCredential) async throws -> CallLinkState
    ) async throws {
        let authCredentialManager = AppEnvironment.shared.callService.authCredentialManager
        let callLinkManager = AppEnvironment.shared.callService.callLinkManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
        let authCredential = try await authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
        self.callLinkState = try await performUpdate(callLinkManager, authCredential)
        updateContents(shouldReload: true)
    }

    // MARK: - Share Via Signal

    private var sendMessageFlow: SendMessageFlow?

    func shareCallLinkViaSignal() {
        let messageBody = MessageBody(text: callLink.url().absoluteString, ranges: .empty)
        let unapprovedContent = SendMessageUnapprovedContent.text(messageBody: messageBody)
        let sendMessageFlow = SendMessageFlow(
            flowType: .`default`,
            unapprovedContent: unapprovedContent,
            useConversationComposeForSingleRecipient: true,
            presentationStyle: .presentFrom(self),
            delegate: self
        )
        // Retain the flow until it is complete.
        self.sendMessageFlow = sendMessageFlow
    }
}

extension CreateCallLinkViewController: SendMessageDelegate {
    func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow?.dismissNavigationController(animated: true)

        sendMessageFlow = nil
    }

    func sendMessageFlowDidCancel() {
        AssertIsOnMainThread()

        sendMessageFlow?.dismissNavigationController(animated: true)

        sendMessageFlow = nil
    }
}

// MARK: -

private class _CreateCallLinkViewController: OWSTableViewController2 {
    override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    override var navbarBackgroundColorOverride: UIColor? { tableBackgroundColor }
}

// MARK: - CallLinkCardView

private class CallLinkCardView: UIView {
    private lazy var circleView: UIView = {
        return SignalUI.CallLinkComponentFactory.callLinkIconView()
    }()

    private lazy var textStack: UIStackView = {
        let stackView = UIStackView()

        let nameLabel = UILabel()
        nameLabel.text = callLinkState.localizedName
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.numberOfLines = 0
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.font = .dynamicTypeHeadline

        let linkLabel = UILabel()
        linkLabel.text = callLink.url().absoluteString
        linkLabel.lineBreakMode = .byTruncatingTail
        linkLabel.numberOfLines = 2

        linkLabel.textColor = Theme.snippetColor
        linkLabel.font = .dynamicTypeBody2

        stackView.addArrangedSubviews([nameLabel, linkLabel])
        stackView.axis = .vertical
        stackView.spacing = Constants.textStackSpacing
        stackView.alignment = .leading

        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let joinButton: UIButton

    private class JoinButton: UIButton {
        init(joinAction: @escaping () -> Void) {
            super.init(frame: .zero)

            let view = UIView()
            view.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
            view.isUserInteractionEnabled = false
            view.layer.cornerRadius = bounds.size.height / 2

            let label = UILabel()
            label.setCompressionResistanceHigh()
            label.text = CallStrings.joinCallPillButtonTitle
            label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
            label.textColor = Theme.accentBlueColor
            view.isUserInteractionEnabled = false

            self.clipsToBounds = true
            self.addAction(UIAction(handler: { _ in joinAction() }), for: .touchUpInside)

            view.addSubview(label)
            label.autoPinEdge(.top, to: .top, of: view, withOffset: Constants.vMargin)
            label.autoPinEdge(.bottom, to: .bottom, of: view, withOffset: -Constants.vMargin)
            label.autoPinEdge(.leading, to: .leading, of: view, withOffset: Constants.hMargin)
            label.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -Constants.hMargin)

            self.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()

            self.accessibilityLabel = CallStrings.joinCallPillButtonTitle
        }

        override public var bounds: CGRect {
            didSet {
                updateRadius()
            }
        }

        private func updateRadius() {
            layer.cornerRadius = bounds.size.height / 2
        }

        private enum Constants {
            static let vMargin: CGFloat = 4
            static let hMargin: CGFloat = 12
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private let callLink: CallLink
    private let callLinkState: CallLinkState

    init(
        callLink: CallLink,
        callLinkState: CallLinkState,
        joinAction: @escaping () -> Void
    ) {
        self.callLink = callLink
        self.callLinkState = callLinkState
        self.joinButton = JoinButton(joinAction: joinAction)

        super.init(frame: .zero)

        let stackView = UIStackView()
        stackView.addArrangedSubviews([circleView, textStack, joinButton])
        stackView.axis = .horizontal
        stackView.distribution = .fillProportionally
        stackView.alignment = .center
        stackView.spacing = Constants.spacingIconToText
        stackView.setCustomSpacing(Constants.spacingTextToButton, after: textStack)

        self.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private enum Constants {
        static let spacingTextToButton: CGFloat = 16
        static let spacingIconToText: CGFloat = 12
        static let textStackSpacing: CGFloat = 2
    }
}
