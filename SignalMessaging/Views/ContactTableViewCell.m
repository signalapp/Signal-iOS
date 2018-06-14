//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "OWSUserProfile.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kContactTableViewCellAvatarSize = 48;
const CGFloat kContactTableViewCellAvatarTextMargin = 12;

@interface ContactTableViewCell ()

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *profileNameLabel;
@property (nonatomic) UIImageView *avatarView;
@property (nonatomic) UILabel *subtitle;
@property (nonatomic) UIView *nameContainerView;

@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) NSString *recipientId;

@end

@implementation ContactTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self configureProgrammatically];
    }
    return self;
}

+ (NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (void)configureProgrammatically
{
    OWSAssert(!self.nameLabel);

    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    _avatarView = [AvatarImageView new];
    [self.contentView addSubview:_avatarView];

    _nameContainerView = [UIView containerView];
    [self.contentView addSubview:_nameContainerView];

    _nameLabel = [UILabel new];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_nameContainerView addSubview:_nameLabel];

    _profileNameLabel = [UILabel new];
    _profileNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _profileNameLabel.textColor = [UIColor grayColor];
    [_nameContainerView addSubview:_profileNameLabel];

    _subtitle = [UILabel new];
    _subtitle.textColor = [UIColor ows_darkGrayColor];
    [_nameContainerView addSubview:self.subtitle];

    [_avatarView autoVCenterInSuperview];
    [_avatarView autoPinLeadingToSuperviewMargin];
    [_avatarView autoSetDimension:ALDimensionWidth toSize:kContactTableViewCellAvatarSize];
    [_avatarView autoSetDimension:ALDimensionHeight toSize:kContactTableViewCellAvatarSize];

    [_nameLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [_nameLabel autoPinWidthToSuperview];

    // profileNameLabel can be zero sized, in which case nameLabel essentially occupies the totality of
    // nameContainerView's frame.
    [_profileNameLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_nameLabel];
    [_profileNameLabel autoPinWidthToSuperview];

    [_subtitle autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_profileNameLabel];
    [_subtitle autoPinWidthToSuperview];
    [_subtitle autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [_nameContainerView autoVCenterInSuperview];
    [_nameContainerView autoPinLeadingToTrailingEdgeOfView:_avatarView offset:kContactTableViewCellAvatarTextMargin];
    [_nameContainerView autoPinTrailingToSuperviewMargin];

    // Ensure that the cell's contents never overflow the cell bounds.
    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    [self.nameContainerView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [self.nameContainerView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];

    [self configureFonts];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureFonts
{
    self.nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    self.profileNameLabel.font = [UIFont ows_regularFontWithSize:11.f];
    self.subtitle.font = [UIFont ows_regularFontWithSize:11.f];
}

- (void)configureWithSignalAccount:(SignalAccount *)signalAccount contactsManager:(OWSContactsManager *)contactsManager
{
    [self configureWithRecipientId:signalAccount.recipientId contactsManager:contactsManager];
}

- (void)configureWithRecipientId:(NSString *)recipientId contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(contactsManager);

    // Update fonts to reflect changes to dynamic type.
    [self configureFonts];

    self.recipientId = recipientId;
    self.contactsManager = contactsManager;

    self.nameLabel.attributedText =
        [contactsManager formattedFullNameForRecipientId:recipientId font:self.nameLabel.font];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
    [self updateProfileName];
    [self updateAvatar];

    if (self.accessoryMessage) {
        UILabel *blockedLabel = [[UILabel alloc] init];
        blockedLabel.textAlignment = NSTextAlignmentRight;
        blockedLabel.text = self.accessoryMessage;
        blockedLabel.font = [UIFont ows_mediumFontWithSize:13.f];
        blockedLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
        [blockedLabel sizeToFit];

        self.accessoryView = blockedLabel;
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssert(thread);

    // Update fonts to reflect changes to dynamic type.
    [self configureFonts];

    self.contactsManager = contactsManager;

    NSString *threadName = thread.name;
    if (threadName.length == 0 && [thread isKindOfClass:[TSGroupThread class]]) {
        threadName = [MessageStrings newGroupDefaultTitle];
    }

    NSAttributedString *attributedText =
        [[NSAttributedString alloc] initWithString:threadName
                                        attributes:@{
                                            NSForegroundColorAttributeName : [UIColor blackColor],
                                        }];
    self.nameLabel.attributedText = attributedText;

    if ([thread isKindOfClass:[TSContactThread class]]) {
        self.recipientId = thread.contactIdentifier;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(otherUsersProfileDidChange:)
                                                     name:kNSNotificationName_OtherUsersProfileDidChange
                                                   object:nil];
        [self updateProfileName];
    }
    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread
                                                         diameter:kContactTableViewCellAvatarSize
                                                  contactsManager:contactsManager];

    if (self.accessoryMessage) {
        UILabel *blockedLabel = [[UILabel alloc] init];
        blockedLabel.textAlignment = NSTextAlignmentRight;
        blockedLabel.text = self.accessoryMessage;
        blockedLabel.font = [UIFont ows_mediumFontWithSize:13.f];
        blockedLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
        [blockedLabel sizeToFit];
        
        self.accessoryView = blockedLabel;
    }
    
    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (NSAttributedString *)verifiedSubtitle
{
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    // "checkmark"
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:@"\uf00c "
                                         attributes:@{
                                             NSFontAttributeName :
                                                 [UIFont ows_fontAwesomeFont:self.subtitle.font.pointSize],
                                         }]];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                        @"Badge indicating that the user is verified.")]];
    return [text copy];
}

- (void)updateAvatar
{
    OWSContactsManager *contactsManager = self.contactsManager;
    if (contactsManager == nil) {
        OWSFail(@"%@ contactsManager should not be nil", self.logTag);
        self.avatarView.image = nil;
        return;
    }

    NSString *recipientId = self.recipientId;
    if (recipientId.length == 0) {
        OWSFail(@"%@ recipientId should not be nil", self.logTag);
        self.avatarView.image = nil;
        return;
    }

    self.avatarView.image = [[[OWSContactAvatarBuilder alloc] initWithSignalId:recipientId
                                                                      diameter:kContactTableViewCellAvatarSize
                                                               contactsManager:contactsManager] build];
}

- (void)updateProfileName
{
    OWSContactsManager *contactsManager = self.contactsManager;
    if (contactsManager == nil) {
        OWSFail(@"%@ contactsManager should not be nil", self.logTag);
        self.profileNameLabel.text = nil;
        return;
    }

    NSString *recipientId = self.recipientId;
    if (recipientId.length == 0) {
        OWSFail(@"%@ recipientId should not be nil", self.logTag);
        self.profileNameLabel.text = nil;
        return;
    }

    if ([contactsManager hasNameInSystemContactsForRecipientId:recipientId]) {
        // Don't display profile name when we have a veritas name in system Contacts
        self.profileNameLabel.text = nil;
    } else {
        // Use profile name, if any is available
        self.profileNameLabel.text = [contactsManager formattedProfileNameForRecipientId:recipientId];
    }

    [self.profileNameLabel setNeedsLayout];
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    self.accessoryMessage = nil;
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.nameLabel.text = nil;
    self.subtitle.text = nil;
    self.profileNameLabel.text = nil;
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssert(recipientId.length > 0);

    if (recipientId.length > 0 && [self.recipientId isEqualToString:recipientId]) {
        [self updateProfileName];
        [self updateAvatar];
    }
}

@end

NS_ASSUME_NONNULL_END
