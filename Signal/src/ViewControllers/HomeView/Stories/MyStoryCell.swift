//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging
import SignalUI

class MyStoryCell: UITableViewCell {
    static let reuseIdentifier = "MyStoryCell"

    let titleLabel = UILabel()
    let titleChevron = UIImageView()
    let subtitleLabel = UILabel()
    let avatarView = ConversationAvatarView(sizeClass: .fiftySix, localUserDisplayMode: .asUser, badged: false, useAutolayout: true)
    let attachmentThumbnail = UIView()

    let failedIconView = UIImageView()

    let addStoryButton = OWSButton()
    private let plusIcon = PlusIconView()

    let contentHStackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        titleLabel.text = NSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        let chevronImage = CurrentAppContext().isRTL ? UIImage(named: "chevron-left-20")! : UIImage(named: "chevron-right-20")!

        titleChevron.image = chevronImage.withRenderingMode(.alwaysTemplate)

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

        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var attachmentThumbnailDividerView: UIView?

    private var latestMessageAttachment: StoryThumbnailView.Attachment?
    private var secondLatestMessageAttachment: StoryThumbnailView.Attachment?

    func configure(with model: MyStoryViewModel, addStoryAction: @escaping () -> Void) {
        configureSubtitle(with: model)

        self.backgroundColor = .clear

        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = Theme.primaryTextColor

        titleChevron.tintColor = Theme.primaryTextColor
        titleChevron.isHiddenInStackView = model.messages.isEmpty

        addStoryButton.block = addStoryAction

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(Self.tsAccountManager.localAddress!)
            // We reload the row when this state changes, so don't make the avatar auto update.
            config.storyConfiguration = .fixed(model.messages.isEmpty ? .noStories : .viewed)
            config.usePlaceholderImages()
        }

        if self.latestMessageAttachment != model.latestMessageAttachment ||
            self.secondLatestMessageAttachment != model.secondLatestMessageAttachment {
            self.latestMessageAttachment = model.latestMessageAttachment
            self.secondLatestMessageAttachment = model.secondLatestMessageAttachment

            attachmentThumbnail.removeAllSubviews()
            attachmentThumbnailDividerView = nil

            if let latestMessageAttachment = model.latestMessageAttachment {
                attachmentThumbnail.isHiddenInStackView = false

                let latestThumbnailView = StoryThumbnailView(attachment: latestMessageAttachment)
                attachmentThumbnail.addSubview(latestThumbnailView)
                latestThumbnailView.autoPinHeightToSuperview()
                latestThumbnailView.autoSetDimensions(to: CGSize(width: 56, height: 84))
                latestThumbnailView.autoPinEdge(toSuperviewEdge: .trailing)

                if let secondLatestMessageAttachment = model.secondLatestMessageAttachment {
                    let secondLatestThumbnailView = StoryThumbnailView(attachment: secondLatestMessageAttachment)
                    secondLatestThumbnailView.layer.cornerRadius = 6
                    secondLatestThumbnailView.transform = .init(rotationAngle: (CurrentAppContext().isRTL ? 1 : -1) * 0.18168878)
                    attachmentThumbnail.insertSubview(secondLatestThumbnailView, belowSubview: latestThumbnailView)
                    secondLatestThumbnailView.autoPinEdge(toSuperviewEdge: .top, withInset: 4)
                    secondLatestThumbnailView.autoSetDimensions(to: CGSize(width: 43, height: 64))
                    secondLatestThumbnailView.autoPinEdge(toSuperviewEdge: .leading)

                    let dividerView = UIView()
                    dividerView.backgroundColor = Theme.backgroundColor
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

        let selectedBackgroundView = SelectedBackgroundView()
        selectedBackgroundView.backgroundColor = Theme.tableCell2SelectedBackgroundColor2
        self.selectedBackgroundView = selectedBackgroundView

        updateColors()
    }

    func configureSubtitle(with model: MyStoryViewModel) {
        subtitleLabel.font = .dynamicTypeSubheadline
        subtitleLabel.textColor = Theme.isDarkThemeEnabled ? Theme.secondaryTextAndIconColor : .ows_gray45
        failedIconView.image = Theme.iconImage(.error16)

        if model.sendingCount > 0 {
            let format = NSLocalizedString("STORY_SENDING_%d", tableName: "PluralAware", comment: "Indicates that N stories are currently sending")
            subtitleLabel.text = .localizedStringWithFormat(format, model.sendingCount)
            failedIconView.isHiddenInStackView = model.failureState == .none
        } else if model.failureState != .none {
            switch model.failureState {
            case .complete:
                subtitleLabel.text = NSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed")
            case .partial:
                subtitleLabel.text = NSLocalizedString("STORY_SEND_PARTIALLY_FAILED", comment: "Text indicating that the story send has partially failed")
            case .none:
                owsFailDebug("Unexpected")
            }
            failedIconView.isHiddenInStackView = false
        } else if let latestMessageTimestamp = model.latestMessageTimestamp {
            subtitleLabel.text = DateUtil.formatTimestampRelatively(latestMessageTimestamp)
            failedIconView.isHiddenInStackView = true
        } else {
            subtitleLabel.text = NSLocalizedString("MY_STORY_TAP_TO_ADD", comment: "Prompt to add to your story")
            failedIconView.isHiddenInStackView = true
        }

        updateColors()
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)

        updateColors()
    }

    private var showingSelectedBackgroundView = false

    public func updateColors() {
        guard
            showingSelectedBackgroundView,
            let backgroundView = self.selectedBackgroundView
        else {
            attachmentThumbnailDividerView?.alpha = 1
            attachmentThumbnailDividerView?.backgroundColor = Theme.backgroundColor
            plusIcon.borderColor = Theme.backgroundColor
            return
        }
        attachmentThumbnailDividerView?.alpha = backgroundView.alpha
        attachmentThumbnailDividerView?.backgroundColor = backgroundView.backgroundColor
        plusIcon.borderColor = backgroundView.backgroundColor?.withAlphaComponent(backgroundView.alpha)
    }

    private class SelectedBackgroundView: UIView {

        override func willMove(toSuperview newSuperview: UIView?) {
            if let cell = newSuperview as? MyStoryCell {
                cell.showingSelectedBackgroundView = true
                cell.updateColors()
            } else if let cell = superview as? MyStoryCell {
                cell.showingSelectedBackgroundView = false
                cell.updateColors()
            }
        }

        override var alpha: CGFloat {
            didSet {
                if let cell = superview as? MyStoryCell {
                    cell.updateColors()
                }
            }
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

            iconView.image = #imageLiteral(resourceName: "plus-my-story").withRenderingMode(.alwaysTemplate)
            iconView.tintColor = .white
            iconView.contentMode = .center
            iconView.autoSetDimensions(to: .square(20))
            iconView.layer.cornerRadius = 10
            iconView.autoCenterInSuperview()
            iconView.backgroundColor = .ows_accentBlue

            // NOTE: gets written over by the cell's theme application.
            outerCircle.backgroundColor = Theme.backgroundColor
            outerCircle.autoSetDimensions(to: .square(26))
            outerCircle.layer.cornerRadius = 13
            outerCircle.autoPinEdgesToSuperviewEdges()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
