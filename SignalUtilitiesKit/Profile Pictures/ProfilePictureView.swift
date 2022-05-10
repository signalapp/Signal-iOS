// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit
import SessionMessagingKit

@objc(LKProfilePictureView)
public final class ProfilePictureView: UIView {
    public static func closedGroupProfileQuery(threadId: String, userPublicKey: String) -> QueryInterfaceRequest<Profile> {
        return Profile
            .filter(Profile.Columns.id != userPublicKey)
            .joining(
                required: Profile.groupMembers
                    .filter(GroupMember.Columns.groupId == threadId)
            )
            .order(.id)
            .limit(2)
    }
         
    private var hasTappableProfilePicture: Bool = false
    @objc public var size: CGFloat = 0 // Not an implicitly unwrapped optional due to Obj-C limitations
    
    // Constraints
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
    private var additionalImageViewWidthConstraint: NSLayoutConstraint!
    private var additionalImageViewHeightConstraint: NSLayoutConstraint!
    
    // MARK: - Components
    
    private lazy var imageView = getImageView()
    private lazy var additionalImageView = getImageView()
    
    // MARK: - Lifecycle
    
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
    
    // FIXME: Look to deprecate this and replace it with the pattern in HomeViewModel (screen should fetch only the required info)
    @objc(updateForThreadId:)
    public func update(forThreadId threadId: String?) {
        guard
            let threadId: String = threadId,
            let (thread, profiles, imageData) = GRDBStorage.shared.read({ db -> (SessionThread, [Profile], Data?) in
                guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else {
                    throw GRDBStorageError.objectNotFound
                }
                
                switch thread.variant {
                    case .contact:
                        return (
                            thread,
                            [try? Profile.fetchOne(db, id: thread.id)].compactMap { $0 },
                            nil
                        )
                        
                    case .closedGroup:
                        let userPublicKey: String = getUserHexEncodedPublicKey(db)
                        let randomUsers: [Profile] = (try? ProfilePictureView
                            .closedGroupProfileQuery(threadId: thread.id, userPublicKey: userPublicKey)
                            .fetchAll(db))
                            .defaulting(to: [])
                        
                        // If there is only a single user in the group then insert the current user
                        // at the back
                        if randomUsers.count == 1 {
                            return (
                                thread,
                                randomUsers.inserting(
                                    Profile.fetchOrCreateCurrentUser(db),
                                    at: 0
                                ),
                                nil
                            )
                        }
                        
                        return (thread, randomUsers, nil)
                        
                    case .openGroup:
                        return (
                            thread,
                            [],
                            try? thread.openGroup
                                .select(OpenGroup.Columns.imageData)
                                .asRequest(of: Data.self)
                                .fetchOne(db)
                        )
                }
            })
        else { return }
        
        update(
            publicKey: (imageData != nil ? "" : thread.id),
            profile: profiles.first,
            additionalProfile: profiles.last,
            threadVariant: thread.variant,
            openGroupProfilePicture: imageData.map { UIImage(data: $0) },
            useFallbackPicture: (thread.variant == .openGroup && imageData == nil)
        )
    }

    public func update(
        publicKey: String = "",
        profile: Profile? = nil,
        additionalProfile: Profile? = nil,
        threadVariant: SessionThread.Variant,
        openGroupProfilePicture: UIImage? = nil,
        useFallbackPicture: Bool = false
    ) {
        AssertIsOnMainThread()
        guard !useFallbackPicture else {
            switch self.size {
                case Values.smallProfilePictureSize..<Values.mediumProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite16")
                case Values.mediumProfilePictureSize..<Values.largeProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite24")
                default: imageView.image = #imageLiteral(resourceName: "SessionWhite40")
            }
            
            imageView.contentMode = .center
            imageView.backgroundColor = UIColor(rgbHex: 0x353535)
            imageView.layer.cornerRadius = (self.size / 2)
            imageViewWidthConstraint.constant = self.size
            imageViewHeightConstraint.constant = self.size
            additionalImageView.isHidden = true
            additionalImageView.image = nil
            additionalImageView.layer.cornerRadius = (self.size / 2)
            return
        }
        guard !publicKey.isEmpty || openGroupProfilePicture != nil else { return }
        
        func getProfilePicture(of size: CGFloat, for publicKey: String, profile: Profile?) -> (image: UIImage, isTappable: Bool) {
            if let profile: Profile = profile, let profilePicture: UIImage = ProfileManager.profileAvatar(profile: profile) {
                return (profilePicture, true)
            }
            
            return (
                Identicon.generatePlaceholderIcon(
                    seed: publicKey,
                    text: (profile?.displayName(for: threadVariant))
                        .defaulting(to: publicKey),
                    size: size
                ),
                false
            )
        }
        
        // Calulate the sizes (and set the additional image content
        let targetSize: CGFloat
        if let additionalProfile: Profile = additionalProfile, openGroupProfilePicture == nil {
            if self.size == 40 {
                targetSize = 32
            }
            else if self.size == Values.largeProfilePictureSize {
                targetSize = 56
            }
            else {
                targetSize = Values.smallProfilePictureSize
            }
            
            imageViewWidthConstraint.constant = targetSize
            imageViewHeightConstraint.constant = targetSize
            additionalImageViewWidthConstraint.constant = targetSize
            additionalImageViewHeightConstraint.constant = targetSize
            additionalImageView.isHidden = false
            additionalImageView.image = getProfilePicture(
                of: targetSize,
                for: additionalProfile.id,
                profile: additionalProfile
            ).image
        }
        else {
            targetSize = self.size
            imageViewWidthConstraint.constant = targetSize
            imageViewHeightConstraint.constant = targetSize
            additionalImageView.isHidden = true
            additionalImageView.image = nil
        }
        
        // Set the image
        if let openGroupProfilePicture: UIImage = openGroupProfilePicture {
            imageView.image = openGroupProfilePicture
            hasTappableProfilePicture = true
        }
        else {
            let (image, isTappable): (UIImage, Bool) = getProfilePicture(
                of: targetSize,
                for: publicKey,
                profile: profile
            )
            imageView.image = image
            hasTappableProfilePicture = isTappable
        }
        
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = Colors.unimportant
        imageView.layer.cornerRadius = (targetSize / 2)
        additionalImageView.layer.cornerRadius = (targetSize / 2)
    }
    
    // MARK: - Convenience
    
    private func getImageView() -> UIImageView {
        let result = UIImageView()
        result.layer.masksToBounds = true
        result.backgroundColor = Colors.unimportant
        result.contentMode = .scaleAspectFit
        
        return result
    }
    
    @objc public func getProfilePicture() -> UIImage? {
        return (hasTappableProfilePicture ? imageView.image : nil)
    }
}
