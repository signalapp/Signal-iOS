//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// For internal (nightly) use only. Produces MessageBackupErrorPresenterInternal.
class MessageBackupErrorPresenterFactoryInternal: MessageBackupErrorPresenterFactory {
    func build(
        appReadiness: AppReadiness,
        db: any DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        tsAccountManager: TSAccountManager
    ) -> MessageBackupErrorPresenter {
        return MessageBackupErrorPresenterInternal(
            appReadiness: appReadiness,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            tsAccountManager: tsAccountManager
        )
    }
}

/// For internal (nightly) use only. Presents MessageBackupInternalErrorViewController when backups emits errors.
class MessageBackupErrorPresenterInternal: MessageBackupErrorPresenter {

    private let appReadiness: AppReadiness
    private let db: any DB
    private let tsAccountManager: TSAccountManager

    private let kvStore: KeyValueStore

    private static let stringifiedErrorsKey = "stringifiedErrors"
    private static let hasBeenDisplayedKey = "hasBeenDisplayed"

    init(
        appReadiness: AppReadiness,
        db: any DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        tsAccountManager: TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.db = db
        self.tsAccountManager = tsAccountManager
        self.kvStore = keyValueStoreFactory.keyValueStore(collection: "MessageBackupErrorPresenterImpl")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presentErrorsIfNeededWithDelay),
            name: .registrationStateDidChange,
            object: nil
        )

        appReadiness.runNowOrWhenUIDidBecomeReadySync { [weak self] in
            self?.presentErrorsIfNeededWithDelay()
        }
    }

    func persistErrors(_ errors: [SignalServiceKit.MessageBackup.CollapsedErrorLog], tx outerTx: DBWriteTransaction) {
        guard FeatureFlags.messageBackupErrorDisplay else {
            return
        }

        if errors.isEmpty {
            return
        }

        let stringified = errors
            .map {
                var text = ($0.typeLogString) + "\n"
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
                self.kvStore.setBool(false, key: Self.hasBeenDisplayedKey, transaction: innerTx)

                innerTx.addAsyncCompletion(on: DispatchQueue.main) { [weak self] in
                    self?.presentErrorsIfNeeded()
                }
            }
        }
    }

    private var forceDuringRegistration = false

    func forcePresentDuringRegistration(completion: @escaping () -> Void) {
        self.forceDuringRegistration = true
        self.presentErrorsIfNeeded(completion: completion)
    }

    @objc
    private func presentErrorsIfNeededWithDelay() {
        // Introduce a small delay to get the UI set up.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
            self.presentErrorsIfNeeded()
        }
    }

    private func presentErrorsIfNeeded(completion: (() -> Void)? = nil) {
        defer { self.forceDuringRegistration = false }
        guard FeatureFlags.messageBackupErrorDisplay else {
            completion?()
            return
        }
        guard forceDuringRegistration || appReadiness.isUIReady else {
            completion?()
            return
        }
        let isRegistered = tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        guard forceDuringRegistration || isRegistered else {
            completion?()
            return
        }
        let errorString: String? = db.write { tx in
            if kvStore.getBool(Self.hasBeenDisplayedKey, defaultValue: false, transaction: tx) {
                return nil
            }
            let errorString = kvStore.getString(Self.stringifiedErrorsKey, transaction: tx)
            kvStore.setBool(true, key: Self.hasBeenDisplayedKey, transaction: tx)
            return errorString
        }
        guard let errorString else {
            completion?()
            return
        }

        let vc = MessageBackupInternalErrorViewController(
            errorString: errorString,
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
        errorString: String,
        isRegistered: Bool,
        completion: (() -> Void)?
    ) {
        self.originalText = errorString
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
