//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI
import UIKit

/// For internal (nightly) use only. Produces MessageBackupErrorPresenterInternal.
class MessageBackupErrorPresenterFactoryInternal: MessageBackupErrorPresenterFactory {
    func build(
        db: any DB,
        tsAccountManager: TSAccountManager
    ) -> MessageBackupErrorPresenter {
        return MessageBackupErrorPresenterInternal(
            db: db,
            tsAccountManager: tsAccountManager
        )
    }
}

/// For internal (nightly) use only. Presents MessageBackupInternalErrorViewController when backups emits errors.
class MessageBackupErrorPresenterInternal: MessageBackupErrorPresenter {

    private let db: any DB
    private let tsAccountManager: TSAccountManager

    private let kvStore: KeyValueStore

    private static let stringifiedErrorsKey = "stringifiedErrors"
    private static let validationErrorKey = "validationError"
    private static let hadFatalErrorKey = "hadFatalError"
    private static let hasBeenDisplayedKey = "hasBeenDisplayed"

    init(
        db: any DB,
        tsAccountManager: TSAccountManager
    ) {
        self.db = db
        self.tsAccountManager = tsAccountManager
        self.kvStore = KeyValueStore(collection: "MessageBackupErrorPresenterImpl")
    }

    func persistErrors(_ errors: [SignalServiceKit.MessageBackup.CollapsedErrorLog], tx outerTx: DBWriteTransaction) {
        guard FeatureFlags.messageBackupErrorDisplay else {
            return
        }

        if errors.isEmpty {
            return
        }

        let hadFatalError = errors.contains(where: \.wasFatal)
        let stringified = errors
            .map {
                var text = ($0.typeLogString) + "\n"
                + "wasFatal: \($0.wasFatal)\n"
                + "Repeated \($0.errorCount) times, from: \($0.idLogStrings)\n"
                + "Example callsite: \($0.exampleCallsiteString)"
                if let exampleProtoFrameJson = $0.exampleProtoFrameJson {
                    text.append("\nProto:\n\(exampleProtoFrameJson)")
                }
                return text
            }
            .joined(separator: "\n-------------------\n")

        // The outer transaction might get rolled back because of these very errors.
        // At the risk of losing these errors in a crash (this is internal only, its fine)
        // do the actual write in a separate transaction (that happens synchronously)
        // so it is never rolled back.
        outerTx.addAsyncCompletion(on: DispatchQueue.global()) { [weak self] in
            guard let self else { return }

            self.db.write { innerTx in
                self.kvStore.setString(stringified, key: Self.stringifiedErrorsKey, transaction: innerTx)
                self.kvStore.setBool(hadFatalError, key: Self.hadFatalErrorKey, transaction: innerTx)
                self.kvStore.setBool(false, key: Self.hasBeenDisplayedKey, transaction: innerTx)
            }
        }
    }

    func persistValidationError(_ error: MessageBackupValidationError) async {
        await self.db.awaitableWrite { tx in
            self.kvStore.setString(error.errorMessage, key: Self.validationErrorKey, transaction: tx)
            self.kvStore.setBool(false, key: Self.hasBeenDisplayedKey, transaction: tx)
        }
    }

    func presentOverTopmostViewController(completion: @escaping () -> Void) {
        guard FeatureFlags.messageBackupErrorDisplay else {
            completion()
            return
        }
        let isRegistered = tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        let errorString: String?
        let hadFatalError: Bool
        let validationErrorString: String?
        (errorString, hadFatalError, validationErrorString) = db.write { tx in
            let hadFatalError = kvStore.getBool(Self.hadFatalErrorKey, defaultValue: false, transaction: tx)
            if kvStore.getBool(Self.hasBeenDisplayedKey, defaultValue: false, transaction: tx) {
                return (nil, hadFatalError, nil)
            }
            let errorString = kvStore.getString(Self.stringifiedErrorsKey, transaction: tx)
            let validationErrorString = self.kvStore.getString(Self.validationErrorKey, transaction: tx)
            kvStore.setBool(true, key: Self.hasBeenDisplayedKey, transaction: tx)
            kvStore.setString(nil, key: Self.stringifiedErrorsKey, transaction: tx)
            kvStore.setString(nil, key: Self.validationErrorKey, transaction: tx)
            return (errorString, hadFatalError, validationErrorString)
        }
        guard errorString != nil || validationErrorString != nil else {
            completion()
            return
        }

        let vc = MessageBackupInternalErrorViewController(
            errorString: errorString,
            hadFatalError: hadFatalError,
            validationErrorString: validationErrorString,
            isRegistered: isRegistered,
            completion: completion
        )
        let navVc = OWSNavigationController(rootViewController: vc)
        UIApplication.shared.frontmostViewController?.present(navVc, animated: true)
    }
}

private class MessageBackupInternalErrorViewController: OWSViewController {

    // MARK: - Properties

    private let originalText: String
    private let completion: (() -> Void)?

    var textView: UITextView!
    let isRegistered: Bool
    let footer = UIToolbar.clear()

    // MARK: Initializers

    fileprivate init(
        errorString: String?,
        hadFatalError: Bool,
        validationErrorString: String?,
        isRegistered: Bool,
        completion: (() -> Void)?
    ) {
        var text: String
        if hadFatalError {
            text = "!!!Backup import or export FAILED!!!"
        } else {
            text = "Backup import or export succeeded with errors"
        }
        text.append("""
            \n\nPlease send the errors below to your nearest iOS dev.\n
            Feel free to edit to remove any private info before sending.\n\n
            """)

        text.append("\n" + AppVersionImpl.shared.currentAppVersion4.debugDescription + "\n")

        if let errorString, let validationErrorString {
            text.append("Hit both iOS and validator errors\n\n")
            text.append("------Validator error------\n")
            text.append(validationErrorString)
            text.append("\n\n------iOS errors------\n")
            text.append(errorString)
        } else  if let errorString {
            text.append(errorString)
        } else  if let validationErrorString {
            text.append("------Validator error------\n")
            text.append(validationErrorString)
        }
        self.originalText = text
        self.isRegistered = isRegistered
        self.completion = completion
        super.init()
    }

    // MARK: View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "Backup errors"

        createViews()

        self.textView.contentOffset = CGPoint(x: 0, y: self.textView.contentInset.top)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        completion?()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        loadContent()
    }

    public func loadContent() {
        view.backgroundColor = Theme.backgroundColor
        textView.backgroundColor = Theme.backgroundColor
        textView.textColor = Theme.primaryTextColor
        footer.tintColor = Theme.primaryIconColor
    }

    // MARK: - Create Views

    private func createViews() {
        view.backgroundColor = Theme.backgroundColor

        let textView = OWSTextView()
        self.textView = textView
        textView.font = UIFont.dynamicTypeBody
        textView.backgroundColor = Theme.backgroundColor
        textView.isOpaque = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = true
        textView.isUserInteractionEnabled = true
        textView.textColor = Theme.primaryTextColor
        textView.text = originalText

        view.addSubview(textView)
        textView.autoPinEdge(toSuperviewEdge: .top)
        textView.autoPinEdge(toSuperviewEdge: .leading)
        textView.autoPinEdge(toSuperviewEdge: .trailing)
        textView.textContainerInset = UIEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        view.addSubview(footer)
        footer.autoPinWidthToSuperview()
        footer.autoPinEdge(.top, to: .bottom, of: textView)
        footer.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        footer.tintColor = Theme.primaryIconColor

        var footerItems = [
            UIBarButtonItem(
                image: Theme.iconImage(.buttonShare),
                style: .plain,
                target: self,
                action: #selector(shareButtonPressed)
            ),
            .flexibleSpace()
        ]
        if isRegistered {
            footerItems.append(.button(icon: .buttonForward, style: .plain) { [weak self] in
                self?.sendAsMessage()
            })
        }
        footer.items = footerItems

        loadContent()
    }

    // MARK: - Actions

    @objc
    private func shareButtonPressed(_ sender: UIBarButtonItem) {
        AttachmentSharing.showShareUI(for: textView.text, sender: sender)
    }

    private func sendAsMessage() {
        ForwardMessageViewController.present(
            forMessageBody: .init(text: textView.text, ranges: .empty),
            from: self,
            delegate: self
        )
    }
}

extension MessageBackupInternalErrorViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem], recipientThreads: [TSThread]) {
        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(
                items: items,
                recipientThreads: recipientThreads,
                fromViewController: self
            )
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }
}
