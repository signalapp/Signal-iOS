//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class StickerSharingViewController: SelectThreadViewController {

    private let stickerPackInfo: StickerPackInfo

    init(stickerPackInfo: StickerPackInfo) {
        self.stickerPackInfo = stickerPackInfo

        super.init()

        self.selectThreadViewDelegate = self
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
        fromViewController.presentFormSheet(modal, animated: true)
    }

    private func shareTo(thread: TSThread) {
        AssertIsOnMainThread()

        let packUrl = stickerPackInfo.shareUrl()

        // Try to include a link preview of the sticker pack.
        firstly { () -> Promise<OWSLinkPreviewDraft?> in
            guard let url = URL(string: packUrl) else {
                throw OWSAssertionError("Invalid url")
            }
            return firstly {
                linkPreviewManager.fetchLinkPreview(for: url)
            }.map(on: .global()) { draft in
                return draft
            }
        }.recover(on: .global()) { error -> Promise<OWSLinkPreviewDraft?> in
            // If link previews are disabled, just share the
            // sticker pack URL.
            if case LinkPreviewError.featureDisabled = error {
                return Promise.value(nil)
            }
            throw error
        }.done { (linkPreviewDraft: OWSLinkPreviewDraft?) in
            self.shareAndDismiss(thread: thread,
                                 packUrl: packUrl,
                                 linkPreviewDraft: linkPreviewDraft)
        }.catch { error in
            owsFailDebug("Could not build link preview: \(error)")

            self.shareAndDismiss(thread: thread,
                                 packUrl: packUrl,
                                 linkPreviewDraft: nil)
        }
    }

    private func shareAndDismiss(thread: TSThread,
                                 packUrl: String,
                                 linkPreviewDraft: OWSLinkPreviewDraft?) {
        AssertIsOnMainThread()

        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(with: MessageBody(text: packUrl, ranges: .empty),
                                      thread: thread,
                                      quotedReplyModel: nil,
                                      linkPreviewDraft: linkPreviewDraft,
                                      transaction: transaction)
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
