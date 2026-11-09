//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SDWebImage
import SignalServiceKit
import SignalUI

class StickerDetailSheet: OWSTableSheetViewController {
    enum StickerContext {
        /// The sticker came from a message in the ConversationViewController.
        case message
        /// The sticker came from a sticker pack.
        case stickerPack
    }

    struct Action {
        let icon: ThemeIcon?
        let title: String
        let handler: () -> Void
    }

    // MARK: -

    private let db: DB
    private let stickerMetadata: any StickerMetadata
    private let stickerManager: StickerManager
    private let actions: [Action]

    init(
        db: DB,
        stickerMetadata: any StickerMetadata,
        stickerManager: StickerManager,
        actions: [Action],
    ) {
        self.db = db
        self.stickerMetadata = stickerMetadata
        self.stickerManager = stickerManager
        self.actions = actions
        super.init()
    }

    // MARK: Sticker preview image

    private func buildPreviewCard() -> UIView? {
        var stickerData: Data
        do {
            stickerData = try stickerMetadata.readStickerData()
        } catch {
            Logger.error("Failure to read sticker metadata")
            return nil
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8

        let animatedImage = SDAnimatedImage(data: stickerData)
        let stickerView = SDAnimatedImageView()
        stickerView.contentMode = .scaleAspectFit
        stickerView.image = animatedImage

        stack.addArrangedSubview(stickerView)

        stickerView.autoSetDimensions(to: .square(240))

        if let subtitleText = fetchSubtitle() {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitleText
            subtitleLabel.font = .dynamicTypeSubheadline
            subtitleLabel.textColor = .Signal.secondaryLabel
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0

            stack.addArrangedSubview(subtitleLabel)
        }

        stack.addArrangedSubview(SpacerView(preferredHeight: 12))

        return stack
    }

    private func fetchSubtitle() -> String? {
        if
            let packRecord = db.read(
                block: { tx in
                    stickerManager.fetchStickerPack(
                        stickerPackInfo: stickerMetadata.packInfo,
                        transaction: tx,
                    )
                },
            ),
            let title = packRecord.title,
            let author = packRecord.author
        {
            return title + " · " + author
        }
        return nil
    }

    // MARK: -

    override func tableContents() -> OWSTableContents {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderView = buildPreviewCard()
        contents.add(section)

        for action in actions {
            section.add(
                .item(
                    icon: action.icon,
                    tintColor: .Signal.label,
                    name: action.title,
                    textColor: .Signal.label,
                    actionBlock: { [weak self] in
                        self?.dismiss(animated: true) {
                            action.handler()
                        }
                    },
                ),
            )
        }

        return contents
    }
}

extension StickerDetailSheet.Action {

    @MainActor
    private static func addToFavoritesAction(
        stickerMetadata: any StickerMetadata,
        stickerManager: StickerManager,
        stickerContext: StickerDetailSheet.StickerContext,
        presentingVC: UIViewController,
    ) -> Self {
        return StickerDetailSheet.Action(
            icon: .favorite,
            title: OWSLocalizedString(
                "STICKER_BUTTON_ADD_FAVORITES",
                comment: "Label for button to add sticker to favorites",
            ),
            handler: { [weak presentingVC] in
                Task {
                    do {
                        try await stickerManager.addStickerToFavorites(stickerMetadata: stickerMetadata)
                    } catch StickerFavoriteError.limitReached {
                        presentingVC?.presentToast(
                            text: String.localizedStringWithFormat(
                                OWSLocalizedString(
                                    "STICKER_FAVORITE_MAX_TOAST_%d",
                                    tableName: "PluralAware",
                                    comment: "Text shown in a toast when the user has reached the max sticker favorite count and cannot add more. Embeds {{ max number of favorite stickers }}",
                                ),
                                StickerManager.maxStickerFavorites,
                            ),
                        )
                        return
                    } catch {
                        owsFailDebug("Failed to add sticker to favorites: \(error)")
                        return
                    }

                    switch stickerContext {
                    case .message:
                        guard let cvc = presentingVC as? ConversationViewController else {
                            owsFailDebug("Sticker context is Message but presenting view is not CVC")
                            return
                        }
                        cvc.openStickerKeyboard(page: .favorites, bouncing: stickerMetadata.stickerInfo)
                    case .stickerPack:
                        presentingVC?.presentToast(
                            text: OWSLocalizedString(
                                "STICKER_ADDED_TO_FAVORITES_TOAST",
                                comment: "Text shown in a toast confirming a sticker was added to favorites",
                            ),
                            image: .favorite,
                        )
                    }
                }
            },
        )
    }

    @MainActor
    private static func removeFromFavoritesAction(
        isPackInstalled: Bool,
        stickerInfo: StickerInfo,
        stickerManager: StickerManager,
        presentingVC: UIViewController,
    ) -> Self {
        return StickerDetailSheet.Action(
            icon: .favoriteSlash,
            title: OWSLocalizedString(
                "STICKER_BUTTON_REMOVE_FAVORITES",
                comment: "Label for button to remove sticker from favorites",
            ),
            handler: { [weak presentingVC] in
                Task {
                    let showToastAction = {
                        presentingVC?.presentToast(
                            text: OWSLocalizedString(
                                "STICKER_REMOVED_FROM_FAVORITES_TOAST",
                                comment: "Text shown in a toast confirming a sticker was removed from favorites",
                            ),
                            image: .favoriteSlash,
                        )
                    }

                    let confirmActionSheet = ActionSheetController(
                        title: OWSLocalizedString(
                            "STICKER_REMOVE_FROM_FAVORITES_CONFIRM_TITLE",
                            comment: "Title for an action sheet asking the user to confirm if they want to remove a sticker from favorites",
                        ),
                        message: OWSLocalizedString(
                            "STICKER_REMOVE_FROM_FAVORITES_CONFIRM_MESSAGE",
                            comment: "Message for an action sheet asking the user to confirm if they want to remove a sticker from favorites",
                        ),
                    )

                    confirmActionSheet.addAction(
                        ActionSheetAction(
                            title: OWSLocalizedString(
                                "STICKER_CONFIRM_REMOVE_BUTTON",
                                comment: "Button to confirm a user wants to remove a sticker",
                            ),
                            style: .destructive,
                            handler: { _ in
                                Task {
                                    await stickerManager.removeStickerFromFavorites(stickerInfo: stickerInfo)
                                    showToastAction()
                                }
                            },
                        ),
                    )
                    confirmActionSheet.addAction(.cancel)

                    presentingVC?.presentActionSheet(confirmActionSheet)
                }
            },
        )
    }

    @MainActor
    static func favoriteAction(
        stickerMetadata: any StickerMetadata,
        db: DB,
        stickerManager: StickerManager,
        presentingVC: UIViewController,
        stickerContext: StickerDetailSheet.StickerContext,
    ) -> Self? {
        let stickerInfo = stickerMetadata.stickerInfo
        let (isFavorited, isPackInstalled) = db.read { tx in
            let isFavorited = stickerManager.isStickerFavorited(
                stickerInfo: stickerInfo,
                tx: tx,
            )
            let isPackInstalled = stickerManager.isStickerPackInstalled(
                stickerPackInfo: stickerMetadata.packInfo,
                transaction: tx,
            )
            return (isFavorited, isPackInstalled)
        }

        if isFavorited {
            return removeFromFavoritesAction(
                isPackInstalled: isPackInstalled,
                stickerInfo: stickerInfo,
                stickerManager: stickerManager,
                presentingVC: presentingVC,
            )
        } else {
            switch stickerContext {
            case .message:
                break
            case .stickerPack:
                guard isPackInstalled else {
                    // Favoriting from an uninstalled pack is not supported when browsing a sticker pack.
                    return nil
                }
            }

            return addToFavoritesAction(
                stickerMetadata: stickerMetadata,
                stickerManager: stickerManager,
                stickerContext: stickerContext,
                presentingVC: presentingVC,
            )
        }
    }
}
