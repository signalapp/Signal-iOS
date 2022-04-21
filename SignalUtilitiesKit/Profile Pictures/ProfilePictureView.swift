// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit
import SessionMessagingKit

@objc(LKProfilePictureView)
public final class ProfilePictureView: UIView {
    private var hasTappableProfilePicture: Bool = false
    @objc public var size: CGFloat = 0 // Not an implicitly unwrapped optional due to Obj-C limitations
    @objc public var useFallbackPicture = false
    @objc public var publicKey: String!
    @objc public var additionalPublicKey: String?
    @objc public var openGroupProfilePicture: UIImage?
    // Constraints
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
    private var additionalImageViewWidthConstraint: NSLayoutConstraint!
    private var additionalImageViewHeightConstraint: NSLayoutConstraint!
    
    // MARK: Components
    private lazy var imageView = getImageView()
    private lazy var additionalImageView = getImageView()
    
    // MARK: Lifecycle
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        // Set up image view
        addSubview(imageView)
        imageView.pin(.leading, to: .leading, of: self)
        imageView.pin(.top, to: .top, of: self)
        let imageViewSize = CGFloat(Values.mediumProfilePictureSize)
        imageViewWidthConstraint = imageView.set(.width, to: imageViewSize)
        imageViewHeightConstraint = imageView.set(.height, to: imageViewSize)
        // Set up additional image view
        addSubview(additionalImageView)
        additionalImageView.pin(.trailing, to: .trailing, of: self)
        additionalImageView.pin(.bottom, to: .bottom, of: self)
        let additionalImageViewSize = CGFloat(Values.smallProfilePictureSize)
        additionalImageViewWidthConstraint = additionalImageView.set(.width, to: additionalImageViewSize)
        additionalImageViewHeightConstraint = additionalImageView.set(.height, to: additionalImageViewSize)
        additionalImageView.layer.cornerRadius = additionalImageViewSize / 2
    }
    
    // MARK: Updating
    @objc(updateForContact:)
    public func update(for publicKey: String) { // TODO: Confirm this is still used
        GRDBStorage.shared.read { db in update(db, publicKey: publicKey) }
    }
        
    public func update(_ db: Database, publicKey: String) {
        openGroupProfilePicture = nil
        self.publicKey = publicKey
        additionalPublicKey = nil
        useFallbackPicture = false
        update(db)
    }

    public func update(_ db: Database, thread: SessionThread) {
        openGroupProfilePicture = nil
        
        switch thread.variant {
            case .contact: update(db, publicKey: thread.id)
                
            case .closedGroup:
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                var randomUsers: [String] = (try? thread.closedGroup
                    .fetchOne(db)?
                    .members
                    .fetchAll(db)
                    .map { $0.profileId }
                    .filter { $0 != userPublicKey }
                    .sorted())   // Sort to provide a level of stability
                    .defaulting(to: [])
                
                if randomUsers.count == 1 {
                    // Ensure the current user is at the back visually
                    randomUsers.insert(userPublicKey, at: 0)
                }
                
                publicKey = (randomUsers.first ?? "")
                additionalPublicKey = (randomUsers.count >= 2 ? randomUsers[1] : "")
                useFallbackPicture = false
                update(db)
                
            case .openGroup:
                openGroupProfilePicture = (try? thread.openGroup
                    .fetchOne(db)?
                    .imageData)
                    .map { UIImage(data: $0) }
                publicKey = ""
                useFallbackPicture = (openGroupProfilePicture == nil)
                hasTappableProfilePicture = (openGroupProfilePicture != nil)
                update(db)
        }
    }

    @objc public func update() { // TODO: Confirm this is still used
        GRDBStorage.shared.read { db in update(db) }
    }
    
    public func update(_ db: Database) {
        AssertIsOnMainThread()
        func getProfilePicture(of size: CGFloat, for publicKey: String) -> UIImage? {
            guard !publicKey.isEmpty else { return nil }
            
            if let profilePicture: UIImage = ProfileManager.profileAvatar(db, id: publicKey) {
                hasTappableProfilePicture = true
                return profilePicture
            }
            
            hasTappableProfilePicture = false
            // TODO: Pass in context?
            let displayName: String = Profile.displayName(db, id: publicKey)
            return Identicon.generatePlaceholderIcon(seed: publicKey, text: displayName, size: size)
        }
        
        let size: CGFloat
        if let additionalPublicKey = additionalPublicKey, !useFallbackPicture, openGroupProfilePicture == nil {
            if self.size == 40 {
                size = 32
            } else if self.size == Values.largeProfilePictureSize {
                size = 56
            } else {
                size = Values.smallProfilePictureSize
            }
            
            imageViewWidthConstraint.constant = size
            imageViewHeightConstraint.constant = size
            additionalImageViewWidthConstraint.constant = size
            additionalImageViewHeightConstraint.constant = size
            additionalImageView.isHidden = false
            additionalImageView.image = getProfilePicture(of: size, for: additionalPublicKey)
        }
        else {
            size = self.size
            imageViewWidthConstraint.constant = size
            imageViewHeightConstraint.constant = size
            additionalImageView.isHidden = true
            additionalImageView.image = nil
        }
        
        guard publicKey != nil || openGroupProfilePicture != nil else { return }
        
        imageView.image = useFallbackPicture ? nil : (openGroupProfilePicture ?? getProfilePicture(of: size, for: publicKey))
        imageView.backgroundColor = useFallbackPicture ? UIColor(rgbHex: 0x353535) : Colors.unimportant
        imageView.layer.cornerRadius = size / 2
        additionalImageView.layer.cornerRadius = size / 2
        imageView.contentMode = useFallbackPicture ? .center : .scaleAspectFit
        
        if useFallbackPicture {
            switch size {
                case Values.smallProfilePictureSize..<Values.mediumProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite16")
                case Values.mediumProfilePictureSize..<Values.largeProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite24")
                default: imageView.image = #imageLiteral(resourceName: "SessionWhite40")
            }
        }
    }
    
    // MARK: Convenience
    private func getImageView() -> UIImageView {
        let result = UIImageView()
        result.layer.masksToBounds = true
        result.backgroundColor = Colors.unimportant
        result.contentMode = .scaleAspectFit
        return result
    }
    
    @objc public func getProfilePicture() -> UIImage? {
        return hasTappableProfilePicture ? imageView.image : nil
    }
}
