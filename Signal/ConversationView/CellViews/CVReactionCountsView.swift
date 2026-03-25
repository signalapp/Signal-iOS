//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class CVReactionCountsView: ManualStackView {

    enum PillState: Equatable {
        case emoji(emoji: String, count: Int, fromLocalUser: Bool)
        case sticker(CVAttachment, emoji: String, count: Int, fromLocalUser: Bool)
        case moreCount(count: Int, fromLocalUser: Bool)

        var fromLocalUser: Bool {
            switch self {
            case .emoji(_, _, let fromLocalUser):
                return fromLocalUser
            case .sticker(_, _, _, let fromLocalUser):
                return fromLocalUser
            case .moreCount(_, let fromLocalUser):
                return fromLocalUser
            }
        }
    }

    struct State: Equatable {
        let pill1: PillState?
        let pill2: PillState?
        let pill3: PillState?
    }

    static let height: CGFloat = 26
    static let inset: CGFloat = 7

    private static let pillKey1 = "pill1"
    private static let pillKey2 = "pill2"
    private static let pillKey3 = "pill3"

    private let pill1 = PillView(pillKey: CVReactionCountsView.pillKey1)
    private let pill2 = PillView(pillKey: CVReactionCountsView.pillKey2)
    private let pill3 = PillView(pillKey: CVReactionCountsView.pillKey3)

    init() {
        super.init(name: "reaction counts")
    }

    static var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal, alignment: .fill, spacing: 0, layoutMargins: .zero)
    }

    static func buildState(with reactionState: InteractionReactionState) -> State {
        func buildPillState(emojiCount: InteractionReactionState.EmojiCount) -> PillState {
            if let sticker = emojiCount.stickerAttachment {
                return .sticker(
                    sticker,
                    emoji: emojiCount.emoji,
                    count: emojiCount.count,
                    fromLocalUser: emojiCount.groupKey == reactionState.localUserReactionGroupKey
                )
            }
            return .emoji(
                emoji: emojiCount.emoji,
                count: emojiCount.count,
                fromLocalUser: emojiCount.groupKey == reactionState.localUserReactionGroupKey
            )
        }

        // We display up to 3 reaction bubbles per message in order
        // of popularity (`emojiCounts` comes pre-sorted to reflect
        // this ordering).

        var pill1: PillState?
        var pill2: PillState?
        var pill3: PillState?
        let build = {
            State(pill1: pill1, pill2: pill2, pill3: pill3)
        }

        guard !reactionState.emojiCounts.isEmpty else {
            return build()
        }

        pill1 = buildPillState(emojiCount: reactionState.emojiCounts[0])

        guard reactionState.emojiCounts.count >= 2 else {
            return build()
        }

        pill2 = buildPillState(emojiCount: reactionState.emojiCounts[1])

        guard reactionState.emojiCounts.count >= 3 else {
            return build()
        }

        // If there are more than 3 unique reactions, the third bubble
        // will represent the count of remaining unique reactors *not*
        // the count of remaining unique emoji.
        if reactionState.emojiCounts.count > 3 {
            let renderedGroupKeys = reactionState.emojiCounts[0...1].map { $0.groupKey }
            let remainingReactorCount = reactionState.emojiCounts
                .lazy
                .filter { !renderedGroupKeys.contains($0.groupKey) }
                .map { $0.count }
                .reduce(0, +)
            let remainingReactionsIncludesLocalUserReaction: Bool = {
                guard
                    let localUserReactionGroupKey = reactionState.localUserReactionGroupKey
                else {
                    return false
                }
                return !renderedGroupKeys.contains(localUserReactionGroupKey)
            }()
            pill3 = .moreCount(
                count: remainingReactorCount,
                fromLocalUser: remainingReactionsIncludesLocalUserReaction,
            )
        } else {
            pill3 = buildPillState(emojiCount: reactionState.emojiCounts[2])
        }

        return build()
    }

    private static let measurementKey = "CVReactionCountsView"

    func configure(
        state: State,
        cellMeasurement: CVCellMeasurement,
        componentView: CVComponentReactions.CVComponentViewReactions,
        mediaCache: CVMediaCache
    ) {

        layer.borderColor = Theme.backgroundColor.cgColor

        var subviews = [UIView]()
        func configure(pillView: PillView, pillState: PillState?, index: Int) {
            guard let pillState else {
                return
            }
            pillView.configure(
                pillState: pillState,
                index: index,
                cellMeasurement: cellMeasurement,
                componentView: componentView,
                mediaCache: mediaCache,
            )
            subviews.append(pillView)
        }
        configure(pillView: pill1, pillState: state.pill1, index: 0)
        configure(pillView: pill2, pillState: state.pill2, index: 1)
        configure(pillView: pill3, pillState: state.pill3, index: 2)

        self.configure(
            config: Self.stackConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey,
            subviews: subviews,
        )
    }

    static func measure(
        state: State,
        measurementBuilder: CVCellMeasurement.Builder,
    ) -> CGSize {
        var subviewInfos = [ManualStackSubviewInfo]()
        func measurePill(pillState: PillState?, pillKey: String) {
            guard let pillState else {
                return
            }
            let pillSize = PillView.measure(
                pillState: pillState,
                pillKey: pillKey,
                measurementBuilder: measurementBuilder,
            )
            subviewInfos.append(pillSize.asManualSubviewInfo)
        }
        measurePill(pillState: state.pill1, pillKey: Self.pillKey1)
        measurePill(pillState: state.pill2, pillKey: Self.pillKey2)
        measurePill(pillState: state.pill3, pillKey: Self.pillKey3)

        let stackMeasurement = ManualStackView.measure(
            config: Self.stackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey,
            subviewInfos: subviewInfos,
        )
        return stackMeasurement.measuredSize
    }

    override func reset() {
        super.reset()

        pill1.reset()
        pill2.reset()
        pill3.reset()
    }

    // MARK: -

    private class PillView: ManualStackViewWithLayer {

        private let pillKey: String

        private let emojiLabel = CVLabel()
        private let countLabel = CVLabel()
        private let stickerSpinner = UIActivityIndicatorView(style: .medium)

        private static let pillBorderWidth: CGFloat = 1
        private static var emojiFont: UIFont {
            .boldSystemFont(ofSize: 14)
        }
        private static var stickerSize: CGFloat {
            // Slightly bigger than the emoji
            emojiFont.lineHeight * 1.75
        }

        init(pillKey: String) {
            self.pillKey = pillKey

            super.init(name: pillKey)

            emojiLabel.clipsToBounds = true
            clipsToBounds = true

            let spinnerSize = Self.stickerSize * 0.75
            stickerSpinner.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stickerSpinner.widthAnchor.constraint(equalToConstant: spinnerSize),
                stickerSpinner.heightAnchor.constraint(equalToConstant: spinnerSize),
            ])
        }

        static var stackConfig: CVStackViewConfig {
            let layoutMargins = UIEdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7)
            return CVStackViewConfig(axis: .horizontal, alignment: .fill, spacing: 2, layoutMargins: layoutMargins)
        }

        static func emojiLabelConfig(pillState: PillState) -> CVLabelConfig? {
            switch pillState {
            case let .sticker(sticker, emoji, _, _):
                switch sticker {
                case .stream, .backupThumbnail:
                    return nil
                case .pointer(_, let downloadState):
                    switch downloadState {
                    case .none, .enqueuedOrDownloading:
                        return nil
                    case .failed:
                        // Fall back to emoji display.
                        break
                    }
                case .undownloadable:
                    // Fall back to emoji display.
                    break
                }
                fallthrough
            case .emoji(let emoji, _, _):
                assert(emoji.isSingleEmoji)

                // textColor doesn't matter for emoji.
                return CVLabelConfig.unstyledText(
                    emoji,
                    font: Self.emojiFont,
                    textColor: .black,
                    textAlignment: .center,
                )
            case .moreCount:
                return nil
            }
        }

        static func countLabelConfig(pillState: PillState) -> CVLabelConfig? {
            let textColor: UIColor = {
                if pillState.fromLocalUser {
                    return Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray90
                } else {
                    return Theme.secondaryTextAndIconColor
                }
            }()

            let text: String
            switch pillState {
            case .emoji(_, let count, _), .sticker(_, _, let count, _):
                guard count > 1 else {
                    return nil
                }
                text = count.abbreviatedString
            case .moreCount(let count, _):
                text = "+" + count.abbreviatedString
            }

            return CVLabelConfig.unstyledText(
                text,
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                textColor: textColor,
                textAlignment: .center,
            )
        }

        private func prepareReusableMediaView(
            attachment: Attachment,
            isAnimated: Bool,
            index: Int,
            componentView: CVComponentReactions.CVComponentViewReactions,
            mediaCache: CVMediaCache,
            mediaViewAdapter: () -> MediaViewAdapter,
        ) -> UIView {
            let cacheKey = CVMediaCache.CacheKey.attachment(attachment.id)
            let reusableMediaView: ReusableMediaView
            if let cached = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
                reusableMediaView = cached
            } else {
                reusableMediaView = ReusableMediaView(mediaViewAdapter: mediaViewAdapter(), mediaCache: mediaCache)
                mediaCache.setMediaView(reusableMediaView, forKey: cacheKey, isAnimated: isAnimated)
            }
            reusableMediaView.owner = componentView
            componentView.reusableMediaViews[index] = reusableMediaView
            reusableMediaView.mediaView.contentMode = .scaleAspectFit
            reusableMediaView.mediaView.clipsToBounds = true
            return reusableMediaView.mediaView
        }

        func configure(
            pillState: PillState,
            index: Int,
            cellMeasurement: CVCellMeasurement,
            componentView: CVComponentReactions.CVComponentViewReactions,
            mediaCache: CVMediaCache,
        ) {
            stickerSpinner.stopAnimating()

            addLayoutBlock { view in
                view.layer.borderWidth = Self.pillBorderWidth
                view.layer.cornerRadius = CVReactionCountsView.height / 2
            }

            layer.borderColor = Theme.backgroundColor.cgColor

            if pillState.fromLocalUser {
                backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray25
            } else {
                backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05
            }

            var subviews = [UIView]()

            switch pillState {
            case
                    .emoji,
                    .moreCount,
                    .sticker(.pointer(_, .failed), _, _, _),
                    .sticker(.undownloadable, _, _, _):
                componentView.reusableMediaViews[index] = nil
            case
                    .sticker(.pointer(_, .none), _, _, _),
                    .sticker(.pointer(_, .enqueuedOrDownloading), _, _, _):
                stickerSpinner.startAnimating()
                subviews.append(stickerSpinner)
                componentView.reusableMediaViews[index] = nil
            case .sticker(.stream(let stream), _, _, _):
                subviews.append(prepareReusableMediaView(
                    attachment: stream.attachment,
                    isAnimated: stream.attachmentStream.contentType.isAnimatedImage,
                    index: index,
                    componentView: componentView,
                    mediaCache: mediaCache,
                    mediaViewAdapter: {
                        MediaViewAdapterSticker(
                            attachmentStream: stream.attachmentStream
                        )
                    }
                ))
            case .sticker(.backupThumbnail(let thumbnail), _, _, _):
                subviews.append(prepareReusableMediaView(
                    attachment: thumbnail.attachment,
                    isAnimated: false,
                    index: index,
                    componentView: componentView,
                    mediaCache: mediaCache,
                    mediaViewAdapter: {
                        MediaViewAdapterBackupThumbnail(
                            attachmentBackupThumbnail: thumbnail.attachmentBackupThumbnail
                        )
                    }
                ))
            }

            if let emojiLabelConfig = Self.emojiLabelConfig(pillState: pillState) {
                emojiLabelConfig.applyForRendering(label: emojiLabel)
                subviews.append(emojiLabel)
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                countLabelConfig.applyForRendering(label: countLabel)
                subviews.append(countLabel)
            }

            configure(
                config: Self.stackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: pillKey,
                subviews: subviews,
            )
        }

        static func measure(
            pillState: PillState,
            pillKey: String,
            measurementBuilder: CVCellMeasurement.Builder,
        ) -> CGSize {

            var subviewInfos = [ManualStackSubviewInfo]()

            if case .sticker(let attachment, _, _, _) = pillState {
                switch attachment {
                case
                        .stream,
                        .backupThumbnail,
                        .pointer(_, .enqueuedOrDownloading),
                        .pointer(_, .none):
                    let size = CGSize(width: stickerSize, height: stickerSize)
                    subviewInfos.append(size.asManualSubviewInfo)
                case .undownloadable, .pointer(_, .failed):
                    break
                }
            }

            if let emojiLabelConfig = Self.emojiLabelConfig(pillState: pillState) {
                let labelSize = CVText.measureLabel(
                    config: emojiLabelConfig,
                    maxWidth: .greatestFiniteMagnitude,
                )
                subviewInfos.append(labelSize.asManualSubviewInfo)
            }

            if let countLabelConfig = Self.countLabelConfig(pillState: pillState) {
                let labelSize = CVText.measureLabel(
                    config: countLabelConfig,
                    maxWidth: .greatestFiniteMagnitude,
                )
                subviewInfos.append(labelSize.asManualSubviewInfo)
            }

            let stackMeasurement = ManualStackView.measure(
                config: Self.stackConfig,
                measurementBuilder: measurementBuilder,
                measurementKey: pillKey,
                subviewInfos: subviewInfos,
            )
            var result = stackMeasurement.measuredSize
            // Pin height.
            result.height = CVReactionCountsView.height
            return result
        }
    }
}
