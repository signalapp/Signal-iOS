//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

class MyStoryCell: UITableViewCell {
    static let reuseIdentifier = "MyStoryCell"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeHeadline
        label.textColor = .Signal.label
        return label
    }()

    private let titleChevron: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .Signal.label
        return imageView
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.secondaryLabel
        return label
    }()

    private let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, badged: false, useAutolayout: true)
    private let attachmentThumbnail = UIView()

    private let failedIconView = UIImageView(image: Theme.iconImage(.error16))

    private let addStoryButton = OWSButton()
    private let plusIcon = PlusIconView()

    private let contentHStackView = UIStackView()

    /// If set to `true` background in `selected` state would have rounded corners.
    var useSidebarAppearance = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        titleLabel.text = OWSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        titleChevron.image = UIImage(imageLiteralResourceName: "chevron-right-20")

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, titleChevron])
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 2

        failedIconView.autoSetDimension(.width, toSize: 16)
        failedIconView.contentMode = .scaleAspectFit
        failedIconView.tintColor = .ows_accentRed

        let subtitleStack = UIStackView(arrangedSubviews: [failedIconView, subtitleLabel])
        subtitleStack.axis = .horizontal
        subtitleStack.alignment = .center
        subtitleStack.spacing = 6

        let vStack = UIStackView(arrangedSubviews: [titleStack, subtitleStack])
        vStack.axis = .vertical
        vStack.alignment = .leading

        addStoryButton.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges()

        plusIcon.isUserInteractionEnabled = false

        addStoryButton.addSubview(plusIcon)
        plusIcon.autoPinEdge(toSuperviewEdge: .trailing, withInset: -3)
        plusIcon.autoPinEdge(toSuperviewEdge: .bottom, withInset: -3)

        contentHStackView.addArrangedSubviews([addStoryButton, vStack, .hStretchingSpacer(), attachmentThumbnail])
        contentHStackView.axis = .horizontal
        contentHStackView.alignment = .center
        contentHStackView.spacing = 16

        contentView.addSubview(contentHStackView)
        contentHStackView.autoPinEdgesToSuperviewMargins()

        attachmentThumbnail.autoSetDimensions(to: CGSize(width: 64, height: 84))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var configuration = UIBackgroundConfiguration.clear()
        if state.isSelected || state.isHighlighted {
            configuration.backgroundColor = Theme.tableCell2SelectedBackgroundColor
            if useSidebarAppearance {
                configuration.cornerRadius = 24
            }
        } else {
            configuration.backgroundColor = .Signal.background
        }
        backgroundConfiguration = configuration

        attachmentThumbnailDividerView?.backgroundColor = configuration.backgroundColor
        plusIcon.borderColor = configuration.backgroundColor
    }

    private var attachmentThumbnailDividerView: UIView?

    private var latestMessageRevealedSpoilerIds: Set<StyleIdType>?
    private var latestMessageAttachment: StoryThumbnailView.Attachment?
    private var secondLatestMessageRevealedSpoilerIds: Set<StyleIdType>?
    private var secondLatestMessageAttachment: StoryThumbnailView.Attachment?

    func configure(
        with model: MyStoryViewModel,
        spoilerState: SpoilerRenderState,
        addStoryAction: @escaping () -> Void,
    ) {
        configureSubtitle(with: model)

        titleChevron.isHiddenInStackView = model.messages.isEmpty

        addStoryButton.block = addStoryAction

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aciAddress)
            // We reload the row when this state changes, so don't make the avatar auto update.
            config.storyConfiguration = .fixed(model.messages.isEmpty ? .noStories : .viewed)
            config.usePlaceholderImages()
        }

        let latestMessageRevealedSpoilerIds: Set<StyleIdType> = model.latestMessageIdentifier.map(
            spoilerState.revealState.revealedSpoilerIds(interactionIdentifier:),
        ) ?? Set()
        let secondLatestMessageRevealedSpoilerIds: Set<StyleIdType> = model.secondLatestMessageIdentifier.map(
            spoilerState.revealState.revealedSpoilerIds(interactionIdentifier:),
        ) ?? Set()

        if
            self.latestMessageAttachment != model.latestMessageAttachment ||
            self.secondLatestMessageAttachment != model.secondLatestMessageAttachment ||
            self.latestMessageRevealedSpoilerIds != latestMessageRevealedSpoilerIds ||
            self.secondLatestMessageRevealedSpoilerIds != secondLatestMessageRevealedSpoilerIds
        {
            self.latestMessageAttachment = model.latestMessageAttachment
            self.secondLatestMessageAttachment = model.secondLatestMessageAttachment
            self.latestMessageRevealedSpoilerIds = latestMessageRevealedSpoilerIds
            self.secondLatestMessageRevealedSpoilerIds = secondLatestMessageRevealedSpoilerIds

            attachmentThumbnail.removeAllSubviews()
            attachmentThumbnailDividerView = nil

            if let latestMessageAttachment = model.latestMessageAttachment, let latestMessageIdentifier = model.latestMessageIdentifier {
                attachmentThumbnail.isHiddenInStackView = false

                let latestThumbnailView = StoryThumbnailView(
                    attachment: latestMessageAttachment,
                    interactionIdentifier: latestMessageIdentifier,
                    spoilerState: spoilerState,
                )
                attachmentThumbnail.addSubview(latestThumbnailView)
                latestThumbnailView.autoPinHeightToSuperview()
                latestThumbnailView.autoSetDimensions(to: CGSize(width: 56, height: 84))
                latestThumbnailView.autoPinEdge(toSuperviewEdge: .trailing)

                if
                    let secondLatestMessageAttachment = model.secondLatestMessageAttachment,
                    let secondLatestMessageIdentifier = model.secondLatestMessageIdentifier
                {
                    let secondLatestThumbnailView = StoryThumbnailView(
                        attachment: secondLatestMessageAttachment,
                        interactionIdentifier: secondLatestMessageIdentifier,
                        spoilerState: spoilerState,
                    )
                    secondLatestThumbnailView.layer.cornerRadius = 6
                    secondLatestThumbnailView.transform = .init(rotationAngle: (CurrentAppContext().isRTL ? 1 : -1) * 0.18168878)
                    attachmentThumbnail.insertSubview(secondLatestThumbnailView, belowSubview: latestThumbnailView)
                    secondLatestThumbnailView.autoPinEdge(toSuperviewEdge: .top, withInset: 4)
                    secondLatestThumbnailView.autoSetDimensions(to: CGSize(width: 43, height: 64))
                    secondLatestThumbnailView.autoPinEdge(toSuperviewEdge: .leading)

                    let dividerView = UIView()
                    dividerView.backgroundColor = .Signal.background
                    dividerView.layer.cornerRadius = 12
                    attachmentThumbnail.insertSubview(dividerView, belowSubview: latestThumbnailView)
                    dividerView.autoSetDimensions(to: CGSize(width: 60, height: 88))
                    dividerView.autoPinEdge(toSuperviewEdge: .trailing, withInset: -2)
                    dividerView.autoPinEdge(toSuperviewEdge: .top, withInset: -2)
                    attachmentThumbnailDividerView = dividerView
                }
            } else {
                attachmentThumbnail.isHiddenInStackView = true
            }
        }
    }

    func configureSubtitle(with model: MyStoryViewModel) {
        if model.sendingCount > 0 {
            let format = OWSLocalizedString("STORY_SENDING_%d", tableName: "PluralAware", comment: "Indicates that N stories are currently sending")
            subtitleLabel.text = String.localizedStringWithFormat(format, model.sendingCount)
            failedIconView.isHiddenInStackView = model.failureState == .none
        } else if model.failureState != .none {
            switch model.failureState {
            case .complete:
                subtitleLabel.text = OWSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed")
            case .partial:
                subtitleLabel.text = OWSLocalizedString("STORY_SEND_PARTIALLY_FAILED", comment: "Text indicating that the story send has partially failed")
            case .none:
                owsFailDebug("Unexpected")
            }
            failedIconView.isHiddenInStackView = false
        } else if let latestMessageTimestamp = model.latestMessageTimestamp {
            subtitleLabel.text = DateUtil.formatTimestampRelatively(latestMessageTimestamp)
            failedIconView.isHiddenInStackView = true
        } else {
            subtitleLabel.text = OWSLocalizedString("MY_STORY_TAP_TO_ADD", comment: "Prompt to add to your story")
            failedIconView.isHiddenInStackView = true
        }
    }

    private class PlusIconView: UIView {

        var borderColor: UIColor? {
            get {
                return outerCircle.backgroundColor
            }
            set {
                outerCircle.backgroundColor = newValue
            }
        }

        let outerCircle = UIView()
        let iconView = UIImageView()

        init() {
            super.init(frame: .zero)

            addSubview(outerCircle)
            addSubview(iconView)

            iconView.image = UIImage(imageLiteralResourceName: "plus-20")
            iconView.tintColor = .white
            iconView.contentMode = .center
            iconView.autoSetDimensions(to: .square(20))
            iconView.layer.cornerRadius = 10
            iconView.autoCenterInSuperview()
            iconView.backgroundColor = .ows_accentBlue

            // NOTE: gets written over by the cell's theme application.
            outerCircle.backgroundColor = .Signal.background
            outerCircle.autoSetDimensions(to: .square(26))
            outerCircle.layer.cornerRadius = 13
            outerCircle.autoPinEdgesToSuperviewEdges()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
