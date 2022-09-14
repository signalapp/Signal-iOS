// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit
import SignalUtilitiesKit

final class MentionSelectionView: UIView, UITableViewDataSource, UITableViewDelegate {
    var candidates: [MentionInfo] = [] {
        didSet {
            tableView.isScrollEnabled = (candidates.count > 4)
            tableView.reloadData()
        }
    }
    
    weak var delegate: MentionSelectionViewDelegate?
    
    var contentOffset: CGPoint {
        get { tableView.contentOffset }
        set { tableView.contentOffset = newValue }
    }

    // MARK: - Components
    
    private lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.dataSource = self
        result.delegate = self
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.register(view: Cell.self)
        
        return result
    }()

    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setUpViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        // Table view
        addSubview(tableView)
        tableView.pin(to: self)
        
        // Top separator
        let topSeparator: UIView = UIView()
        topSeparator.themeBackgroundColor = .borderSeparator
        topSeparator.set(.height, to: Values.separatorThickness)
        addSubview(topSeparator)
        topSeparator.pin(.leading, to: .leading, of: self)
        topSeparator.pin(.top, to: .top, of: self)
        topSeparator.pin(.trailing, to: .trailing, of: self)
        
        // Bottom separator
        let bottomSeparator: UIView = UIView()
        bottomSeparator.themeBackgroundColor = .borderSeparator
        bottomSeparator.set(.height, to: Values.separatorThickness)
        addSubview(bottomSeparator)
        
        bottomSeparator.pin(.leading, to: .leading, of: self)
        bottomSeparator.pin(.trailing, to: .trailing, of: self)
        bottomSeparator.pin(.bottom, to: .bottom, of: self)
    }

    // MARK: - Data
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return candidates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: Cell = tableView.dequeue(type: Cell.self, for: indexPath)
        cell.update(
            with: candidates[indexPath.row].profile,
            threadVariant: candidates[indexPath.row].threadVariant,
            isUserModeratorOrAdmin: OpenGroupManager.isUserModeratorOrAdmin(
                candidates[indexPath.row].profile.id,
                for: candidates[indexPath.row].openGroupRoomToken,
                on: candidates[indexPath.row].openGroupServer
            ),
            isLast: (indexPath.row == (candidates.count - 1))
        )
        
        return cell
    }

    // MARK: - Interaction
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let mentionCandidate = candidates[indexPath.row]
        
        delegate?.handleMentionSelected(mentionCandidate, from: self)
    }
}

// MARK: - Cell

private extension MentionSelectionView {
    final class Cell: UITableViewCell {
        // MARK: - UI
        
        private lazy var profilePictureView: ProfilePictureView = ProfilePictureView()

        private lazy var moderatorIconImageView: UIImageView = UIImageView(image: #imageLiteral(resourceName: "Crown"))

        private lazy var displayNameLabel: UILabel = {
            let result: UILabel = UILabel()
            result.font = .systemFont(ofSize: Values.smallFontSize)
            result.themeTextColor = .textPrimary
            result.lineBreakMode = .byTruncatingTail
            
            return result
        }()

        lazy var separator: UIView = {
            let result: UIView = UIView()
            result.themeBackgroundColor = .borderSeparator
            result.set(.height, to: Values.separatorThickness)
            
            return result
        }()

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
            // Cell background color
            themeBackgroundColor = .settings_tabBackground
            
            // Highlight color
            let selectedBackgroundView = UIView()
            selectedBackgroundView.themeBackgroundColor = .settings_tabHighlight
            self.selectedBackgroundView = selectedBackgroundView
            
            // Profile picture image view
            let profilePictureViewSize = Values.smallProfilePictureSize
            profilePictureView.set(.width, to: profilePictureViewSize)
            profilePictureView.set(.height, to: profilePictureViewSize)
            profilePictureView.size = profilePictureViewSize
            
            // Main stack view
            let mainStackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameLabel ])
            mainStackView.axis = .horizontal
            mainStackView.alignment = .center
            mainStackView.spacing = Values.mediumSpacing
            mainStackView.set(.height, to: profilePictureViewSize)
            contentView.addSubview(mainStackView)
            mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.mediumSpacing)
            mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.smallSpacing)
            contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.mediumSpacing)
            contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.smallSpacing)
            mainStackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
            
            // Moderator icon image view
            moderatorIconImageView.set(.width, to: 20)
            moderatorIconImageView.set(.height, to: 20)
            contentView.addSubview(moderatorIconImageView)
            moderatorIconImageView.pin(.trailing, to: .trailing, of: profilePictureView, withInset: 1)
            moderatorIconImageView.pin(.bottom, to: .bottom, of: profilePictureView, withInset: 4.5)
            
            // Separator
            addSubview(separator)
            separator.pin(.leading, to: .leading, of: self)
            separator.pin(.trailing, to: .trailing, of: self)
            separator.pin(.bottom, to: .bottom, of: self)
        }

        // MARK: - Updating
        
        fileprivate func update(
            with profile: Profile,
            threadVariant: SessionThread.Variant,
            isUserModeratorOrAdmin: Bool,
            isLast: Bool
        ) {
            displayNameLabel.text = profile.displayName(for: threadVariant)
            profilePictureView.update(
                publicKey: profile.id,
                profile: profile,
                threadVariant: threadVariant
            )
            moderatorIconImageView.isHidden = !isUserModeratorOrAdmin
            separator.isHidden = isLast
        }
    }
}

// MARK: - Delegate

protocol MentionSelectionViewDelegate: AnyObject {
    func handleMentionSelected(_ mention: MentionInfo, from view: MentionSelectionView)
}
