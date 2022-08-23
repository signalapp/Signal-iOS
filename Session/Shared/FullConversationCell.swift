// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SignalUtilitiesKit
import SessionMessagingKit

public final class FullConversationCell: UITableViewCell {
    // MARK: - UI
    
    private let accentLineView: UIView = UIView()

    private lazy var profilePictureView: ProfilePictureView = ProfilePictureView()

    private lazy var displayNameLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()

    private lazy var unreadCountView: UIView = {
        let result: UIView = UIView()
        result.backgroundColor = Colors.text.withAlphaComponent(Values.veryLowOpacity)
        let size = FullConversationCell.unreadCountViewSize
        result.set(.width, greaterThanOrEqualTo: size)
        result.set(.height, to: size)
        result.layer.masksToBounds = true
        result.layer.cornerRadius = (size / 2)
        
        return result
    }()

    private lazy var unreadCountLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        
        return result
    }()

    private lazy var hasMentionView: UIView = {
        let result: UIView = UIView()
        result.backgroundColor = Colors.accent
        let size = FullConversationCell.unreadCountViewSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.layer.masksToBounds = true
        result.layer.cornerRadius = (size / 2)
        
        return result
    }()

    private lazy var hasMentionLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.text = "@"
        result.textAlignment = .center
        
        return result
    }()

    private lazy var isPinnedIcon: UIImageView = {
        let result: UIImageView = UIImageView(image: UIImage(named: "Pin")?.withRenderingMode(.alwaysTemplate))
        result.contentMode = .scaleAspectFit
        let size = FullConversationCell.unreadCountViewSize
        result.set(.width, to: size)
        result.set(.height, to: size)
        result.tintColor = Colors.pinIcon
        result.layer.masksToBounds = true
        
        return result
    }()

    private lazy var timestampLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        result.alpha = Values.lowOpacity
        
        return result
    }()

    private lazy var snippetLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()

    private lazy var typingIndicatorView = TypingIndicatorView()

    private lazy var statusIndicatorView: UIImageView = {
        let result: UIImageView = UIImageView()
        result.contentMode = .scaleAspectFit
        result.layer.cornerRadius = (FullConversationCell.statusIndicatorSize / 2)
        result.layer.masksToBounds = true
        
        return result
    }()

    private lazy var topLabelStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.axis = .horizontal
        result.alignment = .center
        result.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        
        return result
    }()

    private lazy var bottomLabelStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.axis = .horizontal
        result.alignment = .center
        result.spacing = Values.smallSpacing / 2 // Effectively Values.smallSpacing because there'll be spacing before and after the invisible spacer
        
        return result
    }()

    // MARK: Settings

    public static let unreadCountViewSize: CGFloat = 20
    private static let statusIndicatorSize: CGFloat = 14

    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        let cellHeight: CGFloat = 68
        
        // Background color
        backgroundColor = Colors.cellBackground
        
        // Highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Colors.cellSelected
        self.selectedBackgroundView = selectedBackgroundView
        
        // Accent line view
        accentLineView.set(.width, to: Values.accentLineThickness)
        accentLineView.set(.height, to: cellHeight)
        
        // Profile picture view
        let profilePictureViewSize = Values.mediumProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        
        // Unread count view
        unreadCountView.addSubview(unreadCountLabel)
        unreadCountLabel.setCompressionResistanceHigh()
        unreadCountLabel.pin([ VerticalEdge.top, VerticalEdge.bottom ], to: unreadCountView)
        unreadCountView.pin(.leading, to: .leading, of: unreadCountLabel, withInset: -4)
        unreadCountView.pin(.trailing, to: .trailing, of: unreadCountLabel, withInset: 4)
        
        // Has mention view
        hasMentionView.addSubview(hasMentionLabel)
        hasMentionLabel.setCompressionResistanceHigh()
        hasMentionLabel.pin(to: hasMentionView)
        
        // Label stack view
        let topLabelSpacer = UIView.hStretchingSpacer()
        [ displayNameLabel, isPinnedIcon, unreadCountView, hasMentionView, topLabelSpacer, timestampLabel ].forEach{ view in
            topLabelStackView.addArrangedSubview(view)
        }
        
        let snippetLabelContainer = UIView()
        snippetLabelContainer.addSubview(snippetLabel)
        snippetLabelContainer.addSubview(typingIndicatorView)
        
        let bottomLabelSpacer = UIView.hStretchingSpacer()
        [ snippetLabelContainer, bottomLabelSpacer, statusIndicatorView ].forEach{ view in
            bottomLabelStackView.addArrangedSubview(view)
        }
        
        let labelContainerView = UIStackView(arrangedSubviews: [ topLabelStackView, bottomLabelStackView ])
        labelContainerView.axis = .vertical
        labelContainerView.alignment = .leading
        labelContainerView.spacing = 6
        labelContainerView.isUserInteractionEnabled = false
        
        // Main stack view
        let stackView = UIStackView(arrangedSubviews: [ accentLineView, profilePictureView, labelContainerView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        contentView.addSubview(stackView)
        
        // Constraints
        accentLineView.pin(.top, to: .top, of: contentView)
        accentLineView.pin(.bottom, to: .bottom, of: contentView)
        timestampLabel.setContentCompressionResistancePriority(.required, for: NSLayoutConstraint.Axis.horizontal)
        
        // HACK: The six lines below are part of a workaround for a weird layout bug
        topLabelStackView.set(.width, to: UIScreen.main.bounds.width - Values.accentLineThickness - profilePictureViewSize - 3 * Values.mediumSpacing)
        topLabelStackView.set(.height, to: 20)
        topLabelSpacer.set(.height, to: 20)
        
        bottomLabelStackView.set(.width, to: UIScreen.main.bounds.width - Values.accentLineThickness - profilePictureViewSize - 3 * Values.mediumSpacing)
        bottomLabelStackView.set(.height, to: 18)
        bottomLabelSpacer.set(.height, to: 18)
        
        statusIndicatorView.set(.width, to: FullConversationCell.statusIndicatorSize)
        statusIndicatorView.set(.height, to: FullConversationCell.statusIndicatorSize)
        
        snippetLabel.pin(to: snippetLabelContainer)
        
        typingIndicatorView.pin(.leading, to: .leading, of: snippetLabelContainer)
        typingIndicatorView.centerYAnchor.constraint(equalTo: snippetLabel.centerYAnchor).isActive = true
        
        stackView.pin(.leading, to: .leading, of: contentView)
        stackView.pin(.top, to: .top, of: contentView)
        
        // HACK: The two lines below are part of a workaround for a weird layout bug
        stackView.set(.width, to: UIScreen.main.bounds.width - Values.mediumSpacing)
        stackView.set(.height, to: cellHeight)
    }
    
    // MARK: - Content
    
    // MARK: --Search Results
    
    public func updateForMessageSearchResult(with cellViewModel: SessionThreadViewModel, searchText: String) {
        profilePictureView.update(
            publicKey: cellViewModel.threadId,
            profile: cellViewModel.profile,
            additionalProfile: cellViewModel.additionalProfile,
            threadVariant: cellViewModel.threadVariant,
            openGroupProfilePictureData: cellViewModel.openGroupProfilePictureData,
            useFallbackPicture: (cellViewModel.threadVariant == .openGroup && cellViewModel.openGroupProfilePictureData == nil)
        )
        
        isPinnedIcon.isHidden = true
        unreadCountView.isHidden = true
        hasMentionView.isHidden = true
        displayNameLabel.attributedText = NSMutableAttributedString(
            string: cellViewModel.displayName,
            attributes: [ .foregroundColor: Colors.text]
        )
        timestampLabel.isHidden = false
        timestampLabel.text = cellViewModel.lastInteractionDate.formattedForDisplay
        bottomLabelStackView.isHidden = false
        snippetLabel.attributedText = getHighlightedSnippet(
            content: Interaction.previewText(
                variant: (cellViewModel.interactionVariant ?? .standardIncoming),
                body: cellViewModel.interactionBody,
                authorDisplayName: cellViewModel.authorName(for: .contact),
                attachmentDescriptionInfo: cellViewModel.interactionAttachmentDescriptionInfo,
                attachmentCount: cellViewModel.interactionAttachmentCount,
                isOpenGroupInvitation: (cellViewModel.interactionIsOpenGroupInvitation == true)
            ),
            authorName: (cellViewModel.authorId != cellViewModel.currentUserPublicKey ?
                cellViewModel.authorName(for: .contact) :
                nil
            ),
            currentUserPublicKey: cellViewModel.currentUserPublicKey,
            currentUserBlindedPublicKey: cellViewModel.currentUserBlindedPublicKey,
            searchText: searchText.lowercased(),
            fontSize: Values.smallFontSize
        )
    }
    
    public func updateForContactAndGroupSearchResult(with cellViewModel: SessionThreadViewModel, searchText: String) {
        profilePictureView.update(
            publicKey: cellViewModel.threadId,
            profile: cellViewModel.profile,
            additionalProfile: cellViewModel.additionalProfile,
            threadVariant: cellViewModel.threadVariant,
            openGroupProfilePictureData: cellViewModel.openGroupProfilePictureData,
            useFallbackPicture: (cellViewModel.threadVariant == .openGroup && cellViewModel.openGroupProfilePictureData == nil)
        )
        
        isPinnedIcon.isHidden = true
        unreadCountView.isHidden = true
        hasMentionView.isHidden = true
        timestampLabel.isHidden = true
        displayNameLabel.attributedText = getHighlightedSnippet(
            content: cellViewModel.displayName,
            currentUserPublicKey: cellViewModel.currentUserPublicKey,
            currentUserBlindedPublicKey: cellViewModel.currentUserBlindedPublicKey,
            searchText: searchText.lowercased(),
            fontSize: Values.mediumFontSize
        )
        
        switch cellViewModel.threadVariant {
            case .contact, .openGroup: bottomLabelStackView.isHidden = true
                
            case .closedGroup:
                bottomLabelStackView.isHidden = (cellViewModel.threadMemberNames ?? "").isEmpty
                snippetLabel.attributedText = getHighlightedSnippet(
                    content: (cellViewModel.threadMemberNames ?? ""),
                    currentUserPublicKey: cellViewModel.currentUserPublicKey,
                    currentUserBlindedPublicKey: cellViewModel.currentUserBlindedPublicKey,
                    searchText: searchText.lowercased(),
                    fontSize: Values.smallFontSize
                )
        }
    }

    // MARK: --Standard
    
    public func update(with cellViewModel: SessionThreadViewModel) {
        let unreadCount: UInt = (cellViewModel.threadUnreadCount ?? 0)
        backgroundColor = (cellViewModel.threadIsPinned ? Colors.cellPinned : Colors.cellBackground)
        
        if cellViewModel.threadIsBlocked == true {
            accentLineView.backgroundColor = Colors.destructive
            accentLineView.alpha = 1
        }
        else {
            accentLineView.backgroundColor = Colors.accent
            accentLineView.alpha = (unreadCount > 0 ? 1 : 0.0001) // Setting the alpha to exactly 0 causes an issue on iOS 12
        }
        
        isPinnedIcon.isHidden = !cellViewModel.threadIsPinned
        unreadCountView.isHidden = (unreadCount <= 0)
        unreadCountLabel.text = (unreadCount < 10000 ? "\(unreadCount)" : "9999+")
        unreadCountLabel.font = .boldSystemFont(
            ofSize: (unreadCount < 10000 ? Values.verySmallFontSize : 8)
        )
        hasMentionView.isHidden = !(
            ((cellViewModel.threadUnreadMentionCount ?? 0) > 0) &&
            (cellViewModel.threadVariant == .closedGroup || cellViewModel.threadVariant == .openGroup)
        )
        profilePictureView.update(
            publicKey: cellViewModel.threadId,
            profile: cellViewModel.profile,
            additionalProfile: cellViewModel.additionalProfile,
            threadVariant: cellViewModel.threadVariant,
            openGroupProfilePictureData: cellViewModel.openGroupProfilePictureData,
            useFallbackPicture: (
                cellViewModel.threadVariant == .openGroup &&
                cellViewModel.openGroupProfilePictureData == nil
            ),
            showMultiAvatarForClosedGroup: true
        )
        displayNameLabel.text = cellViewModel.displayName
        timestampLabel.text = cellViewModel.lastInteractionDate.formattedForDisplay
        
        if cellViewModel.threadContactIsTyping == true {
            snippetLabel.text = ""
            typingIndicatorView.isHidden = false
            typingIndicatorView.startAnimation()
        }
        else {
            snippetLabel.attributedText = getSnippet(cellViewModel: cellViewModel)
            typingIndicatorView.isHidden = true
            typingIndicatorView.stopAnimation()
        }
        
        statusIndicatorView.backgroundColor = nil
        
        switch (cellViewModel.interactionVariant, cellViewModel.interactionState) {
            case (.standardOutgoing, .sending):
                statusIndicatorView.image = #imageLiteral(resourceName: "CircleDotDotDot").withRenderingMode(.alwaysTemplate)
                statusIndicatorView.tintColor = Colors.text
                statusIndicatorView.isHidden = false
                
            case (.standardOutgoing, .sent):
                statusIndicatorView.image = #imageLiteral(resourceName: "CircleCheck").withRenderingMode(.alwaysTemplate)
                statusIndicatorView.tintColor = Colors.text
                statusIndicatorView.isHidden = false
                
            case (.standardOutgoing, .failed):
                statusIndicatorView.image = #imageLiteral(resourceName: "message_status_failed").withRenderingMode(.alwaysTemplate)
                statusIndicatorView.tintColor = Colors.destructive
                statusIndicatorView.isHidden = false
            
            default:
                statusIndicatorView.isHidden = true
        }
    }
    
    // MARK: - Snippet generation

    private func getSnippet(cellViewModel: SessionThreadViewModel) -> NSMutableAttributedString {
        // If we don't have an interaction then do nothing
        guard cellViewModel.interactionId != nil else { return NSMutableAttributedString() }
        
        let result = NSMutableAttributedString()
        
        if Date().timeIntervalSince1970 < (cellViewModel.threadMutedUntilTimestamp ?? 0) {
            result.append(NSAttributedString(
                string: "\u{e067}  ",
                attributes: [
                    .font: UIFont.ows_elegantIconsFont(10),
                    .foregroundColor :Colors.unimportant
                ]
            ))
        }
        else if cellViewModel.threadOnlyNotifyForMentions == true {
            let imageAttachment = NSTextAttachment()
            imageAttachment.image = UIImage(named: "NotifyMentions.png")?.asTintedImage(color: Colors.unimportant)
            imageAttachment.bounds = CGRect(x: 0, y: -2, width: Values.smallFontSize, height: Values.smallFontSize)
            
            let imageString = NSAttributedString(attachment: imageAttachment)
            result.append(imageString)
            result.append(NSAttributedString(
                string: "  ",
                attributes: [
                    .font: UIFont.ows_elegantIconsFont(10),
                    .foregroundColor: Colors.unimportant
                ]
            ))
        }
        
        let font: UIFont = ((cellViewModel.threadUnreadCount ?? 0) > 0 ?
            .boldSystemFont(ofSize: Values.smallFontSize) :
            .systemFont(ofSize: Values.smallFontSize)
        )
        
        if cellViewModel.threadVariant == .closedGroup || cellViewModel.threadVariant == .openGroup {
            let authorName: String = cellViewModel.authorName(for: cellViewModel.threadVariant)
            
            result.append(NSAttributedString(
                string: "\(authorName): ",
                attributes: [
                    .font: font,
                    .foregroundColor: Colors.text
                ]
            ))
        }
        
        result.append(NSAttributedString(
            string: MentionUtilities.highlightMentions(
                in: Interaction.previewText(
                    variant: (cellViewModel.interactionVariant ?? .standardIncoming),
                    body: cellViewModel.interactionBody,
                    threadContactDisplayName: cellViewModel.threadContactName(),
                    authorDisplayName: cellViewModel.authorName(for: cellViewModel.threadVariant),
                    attachmentDescriptionInfo: cellViewModel.interactionAttachmentDescriptionInfo,
                    attachmentCount: cellViewModel.interactionAttachmentCount,
                    isOpenGroupInvitation: (cellViewModel.interactionIsOpenGroupInvitation == true)
                ),
                threadVariant: cellViewModel.threadVariant,
                currentUserPublicKey: cellViewModel.currentUserPublicKey,
                currentUserBlindedPublicKey: cellViewModel.currentUserBlindedPublicKey
            ),
            attributes: [
                .font: font,
                .foregroundColor: Colors.text
            ]
        ))
            
        return result
    }
    
    private func getHighlightedSnippet(
        content: String,
        authorName: String? = nil,
        currentUserPublicKey: String,
        currentUserBlindedPublicKey: String?,
        searchText: String,
        fontSize: CGFloat
    ) -> NSAttributedString {
        guard !content.isEmpty, content != "NOTE_TO_SELF".localized() else {
            return NSMutableAttributedString(
                string: (authorName != nil && authorName?.isEmpty != true ?
                    "\(authorName ?? ""): \(content)" :
                    content
                ),
                attributes: [ .foregroundColor: Colors.text ]
            )
        }
        
        // Replace mentions in the content
        //
        // Note: The 'threadVariant' is used for profile context but in the search results
        // we don't want to include the truncated id as part of the name so we exclude it
        let mentionReplacedContent: String = MentionUtilities.highlightMentions(
            in: content,
            threadVariant: .contact,
            currentUserPublicKey: currentUserPublicKey,
            currentUserBlindedPublicKey: currentUserBlindedPublicKey
        )
        let result: NSMutableAttributedString = NSMutableAttributedString(
            string: mentionReplacedContent,
            attributes: [
                .foregroundColor: Colors.text
                    .withAlphaComponent(Values.lowOpacity)
            ]
        )
        
        // Bold each part of the searh term which matched
        let normalizedSnippet: String = mentionReplacedContent.lowercased()
        var firstMatchRange: Range<String.Index>?
        
        SessionThreadViewModel.searchTermParts(searchText)
            .map { part -> String in
                guard part.hasPrefix("\"") && part.hasSuffix("\"") else { return part }
                
                return String(part[part.index(after: part.startIndex)..<part.endIndex])
            }
            .forEach { part in
                // Highlight all ranges of the text (Note: The search logic only finds results that start
                // with the term so we use the regex below to ensure we only highlight those cases)
                normalizedSnippet
                    .ranges(
                        of: (CurrentAppContext().isRTL ?
                             "\(part.lowercased())(^|[ ])" :
                             "(^|[ ])\(part.lowercased())"
                        ),
                        options: [.regularExpression]
                    )
                    .forEach { range in
                        // Store the range of the first match so we can focus it in the content displayed
                        if firstMatchRange == nil {
                            firstMatchRange = range
                        }
                        
                        let legacyRange: NSRange = NSRange(range, in: normalizedSnippet)
                        result.addAttribute(.foregroundColor, value: Colors.text, range: legacyRange)
                        result.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: fontSize), range: legacyRange)
                    }
            }
        
        // We then want to truncate the content so the first matching term is visible
        let startOfSnippet: String.Index = (
            firstMatchRange.map {
                max(
                    mentionReplacedContent.startIndex,
                    mentionReplacedContent
                        .index(
                            $0.lowerBound,
                            offsetBy: -10,
                            limitedBy: mentionReplacedContent.startIndex
                        )
                        .defaulting(to: mentionReplacedContent.startIndex)
                )
            } ??
            mentionReplacedContent.startIndex
        )
        
        // This method determines if the content is probably too long and returns the truncated or untruncated
        // content accordingly
        func truncatingIfNeeded(approxWidth: CGFloat, content: NSAttributedString) -> NSAttributedString {
            let approxFullWidth: CGFloat = (approxWidth + profilePictureView.size + (Values.mediumSpacing * 3))
            
            guard ((bounds.width - approxFullWidth) < 0) else { return content }
            
            return content.attributedSubstring(
                from: NSRange(startOfSnippet..<normalizedSnippet.endIndex, in: normalizedSnippet)
            )
        }
        
        // Now that we have generated the focused snippet add the author name as a prefix (if provided)
        return authorName
            .map { authorName -> NSAttributedString? in
                guard !authorName.isEmpty else { return nil }
                
                let authorPrefix: NSAttributedString = NSAttributedString(
                    string: "\(authorName): ...",
                    attributes: [ .foregroundColor: Colors.text ]
                )
                
                return authorPrefix
                    .appending(
                        truncatingIfNeeded(
                            approxWidth: (authorPrefix.size().width + result.size().width),
                            content: result
                        )
                    )
            }
            .defaulting(
                to: truncatingIfNeeded(
                    approxWidth: result.size().width,
                    content: result
                )
            )
    }
}
