//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class StickerSharingViewController: SelectThreadViewController {

    // MARK: Dependencies

    var primaryStorage: OWSPrimaryStorage {
        return SSKEnvironment.shared.primaryStorage
    }

    var linkPreviewManager: OWSLinkPreviewManager {
        return SSKEnvironment.shared.linkPreviewManager
    }

    // MARK: -

    private let stickerPackInfo: StickerPackInfo

    init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo

        super.init(nibName: nil, bundle: nil)

        self.selectThreadViewDelegate = self
    }

    required public init(coder: NSCoder) {
        notImplemented()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("STICKERS_PACK_SHARE_VIEW_TITLE", comment: "Title of the 'share sticker pack' view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressCloseButton))
    }

    @objc
    public class func shareStickerPack(_ stickerPackInfo: StickerPackInfo,
                                       from fromViewController: UIViewController) {
        AssertIsOnMainThread()

        let view = StickerSharingViewController(stickerPackInfo: stickerPackInfo)
        let modal = OWSNavigationController(rootViewController: view)
        fromViewController.present(modal, animated: true)
    }

    private func shareTo(thread: TSThread) {
        AssertIsOnMainThread()

        let packUrl = stickerPackInfo.shareUrl()

        // Try to include a link preview of the sticker pack.
        linkPreviewManager.tryToBuildPreviewInfo(previewUrl: packUrl)
            .done { (linkPreviewDraft) in
                self.shareAndDismiss(thread: thread,
                                     packUrl: packUrl,
                                     linkPreviewDraft: linkPreviewDraft)
            }.catch { error in
                owsFailDebug("Could not build link preview: \(error)")

                self.shareAndDismiss(thread: thread,
                                     packUrl: packUrl,
                                     linkPreviewDraft: nil)
            }
            .retainUntilComplete()
    }

    private func shareAndDismiss(thread: TSThread,
                                 packUrl: String,
                                 linkPreviewDraft: OWSLinkPreviewDraft?) {
        AssertIsOnMainThread()

        primaryStorage.dbReadConnection.read { (transaction) in
            ThreadUtil.enqueueMessage(withText: packUrl, in: thread, quotedReplyModel: nil, linkPreviewDraft: linkPreviewDraft, transaction: transaction.asAnyRead)
        }

        self.dismiss(animated: true)
    }

    // MARK: Helpers

    @objc
    private func didPressCloseButton(sender: UIButton) {
        Logger.info("")

        self.dismiss(animated: true)
    }
}

// MARK: -

extension StickerSharingViewController: SelectThreadViewControllerDelegate {
    public func threadWasSelected(_ thread: TSThread) {
        shareTo(thread: thread)
    }

    public func canSelectBlockedContact() -> Bool {
        return false
    }

    public func createHeader(with searchBar: UISearchBar) -> UIView? {
        return nil
    }
}
