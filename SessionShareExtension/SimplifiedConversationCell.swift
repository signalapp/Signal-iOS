import UIKit
import SessionUIKit

final class SimplifiedConversationCell : UITableViewCell {
    var threadViewModel: ThreadViewModel! { didSet { update() } }
    
    static let reuseIdentifier = "SimplifiedConversationCell"
    
    // MARK: UI Components
    private lazy var accentLineView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.destructive
        return result
    }()
    
    private lazy var profilePictureView = ProfilePictureView()
    
    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.textColor = Colors.text
        result.lineBreakMode = .byTruncatingTail
        return result
    }()
    
    // MARK: Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        // Background color
        backgroundColor = Colors.cellBackground
        // Highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Colors.cellSelected
        self.selectedBackgroundView = selectedBackgroundView
        // Accent line view
        accentLineView.set(.width, to: Values.accentLineThickness)
        accentLineView.set(.height, to: 68)
        // Profile picture view
        let profilePictureViewSize = Values.mediumProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        // Main stack view
        let stackView = UIStackView(arrangedSubviews: [ accentLineView, profilePictureView, displayNameLabel ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        addSubview(stackView)
        stackView.pin(to: self)
    }
    
    // MARK: Updating
    private func update() {
        AssertIsOnMainThread()
        guard let thread = threadViewModel?.threadRecord else { return }
        let isBlocked: Bool
        if let thread = thread as? TSContactThread {
            isBlocked = SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(thread.contactSessionID())
        } else {
            isBlocked = false
        }
        accentLineView.alpha = isBlocked ? 1 : 0
        profilePictureView.update(for: thread)
        displayNameLabel.text = getDisplayName()
    }
    
    private func getDisplayName() -> String {
        if threadViewModel.isGroupThread {
            if threadViewModel.name.isEmpty {
                return "Unknown Group"
            } else {
                return threadViewModel.name
            }
        } else {
            if threadViewModel.threadRecord.isNoteToSelf() {
                return NSLocalizedString("NOTE_TO_SELF", comment: "")
            } else {
                let hexEncodedPublicKey = threadViewModel.contactSessionID!
                return Storage.shared.getContact(with: hexEncodedPublicKey)?.displayName(for: .regular) ?? hexEncodedPublicKey
            }
        }
    }
}
