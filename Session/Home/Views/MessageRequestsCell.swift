// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

class MessageRequestsCell: UITableViewCell {
    static let reuseIdentifier = "MessageRequestsCell"
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setUpViewHierarchy()
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setUpViewHierarchy()
        setupLayout()
    }
    
    // MARK: - UI
    
    private let iconContainerView: UIView = {
        let view: UIView = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.backgroundColor = Colors.sessionMessageRequestsBubble
        view.layer.cornerRadius = (Values.mediumProfilePictureSize / 2)
        
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let view: UIImageView = UIImageView(image: #imageLiteral(resourceName: "message_requests").withRenderingMode(.alwaysTemplate))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = Colors.sessionMessageRequestsIcon
        
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label: UILabel = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        label.text = NSLocalizedString("MESSAGE_REQUESTS_TITLE", comment: "")
        label.textColor = Colors.sessionMessageRequestsTitle
        label.lineBreakMode = .byTruncatingTail
        
        return label
    }()
    
    private let unreadCountView: UIView = {
        let view: UIView = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.backgroundColor = Colors.text.withAlphaComponent(Values.veryLowOpacity)
        view.layer.cornerRadius = (ConversationCell.unreadCountViewSize / 2)
        
        return view
    }()
    
    private let unreadCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        label.textColor = Colors.text
        label.textAlignment = .center
        
        return label
    }()
    
    private func setUpViewHierarchy() {
        backgroundColor = Colors.cellBackground
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = Colors.cellSelected
        
        
        contentView.addSubview(iconContainerView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(unreadCountView)
        
        iconContainerView.addSubview(iconImageView)
        unreadCountView.addSubview(unreadCountLabel)
    }
    
    // MARK: - Layout
    
    private func setupLayout() {
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 68),
            
            iconContainerView.leftAnchor.constraint(
                equalTo: contentView.leftAnchor,
                // Need 'accentLineThickness' to line up correctly with the 'ConversationCell'
                constant: (Values.accentLineThickness + Values.mediumSpacing)
            ),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: Values.mediumProfilePictureSize),
            iconContainerView.heightAnchor.constraint(equalToConstant: Values.mediumProfilePictureSize),
            
            iconImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 25),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),
            
            titleLabel.leftAnchor.constraint(equalTo: iconContainerView.rightAnchor, constant: Values.mediumSpacing),
            titleLabel.rightAnchor.constraint(lessThanOrEqualTo: contentView.rightAnchor, constant: -Values.mediumSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            unreadCountView.leftAnchor.constraint(equalTo: titleLabel.rightAnchor, constant: (Values.smallSpacing / 2)),
            unreadCountView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            unreadCountView.widthAnchor.constraint(equalToConstant: ConversationCell.unreadCountViewSize),
            unreadCountView.heightAnchor.constraint(equalToConstant: ConversationCell.unreadCountViewSize),
            
            unreadCountLabel.topAnchor.constraint(equalTo: unreadCountView.topAnchor),
            unreadCountLabel.leftAnchor.constraint(equalTo: unreadCountView.leftAnchor),
            unreadCountLabel.rightAnchor.constraint(equalTo: unreadCountView.rightAnchor),
            unreadCountLabel.bottomAnchor.constraint(equalTo: unreadCountView.bottomAnchor)
        ])
    }
    
    // MARK: - Content
    
    func update(with count: Int) {
        unreadCountLabel.text = "\(count)"
        unreadCountView.isHidden = (count <= 0)
    }
}
