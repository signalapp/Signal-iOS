//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "Environment.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kContactsTable_CellReuseIdentifier = @"kContactsTable_CellReuseIdentifier";
const NSUInteger kContactTableViewCellAvatarSize = 40;

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

- (instancetype)init
{
    if (self = [super init]) {
        [self configureProgrammatically];
    }
    return self;
}

+ (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(self.width, ContactTableViewCell.rowHeight);
}

+ (CGFloat)rowHeight
{
    return 59.f;
}

- (void)configureProgrammatically
{
    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    _avatarView = [AvatarImageView new];
    [self.contentView addSubview:_avatarView];

    _nameContainerView = [UIView containerView];
    [self.contentView addSubview:_nameContainerView];

    _nameLabel = [UILabel new];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    [_nameContainerView addSubview:_nameLabel];

    _profileNameLabel = [UILabel new];
    _profileNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _profileNameLabel.font = [UIFont ows_footnoteFont];
    _profileNameLabel.textColor = [UIColor grayColor];
    [_nameContainerView addSubview:_profileNameLabel];

    _subtitle = [UILabel new];
    _subtitle.font = [UIFont ows_footnoteFont];
    _subtitle.textColor = [UIColor ows_darkGrayColor];
    [_nameContainerView addSubview:self.subtitle];

    [_avatarView autoVCenterInSuperview];
    [_avatarView autoPinLeadingToSuperview];
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
    [_nameContainerView autoPinLeadingToTrailingOfView:_avatarView margin:12.f];
    [_nameContainerView autoPinTrailingToSuperview];

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithSignalAccount:(SignalAccount *)signalAccount contactsManager:(OWSContactsManager *)contactsManager
{
    [self configureWithRecipientId:signalAccount.recipientId
                   contactsManager:contactsManager];
}

- (void)configureWithRecipientId:(NSString *)recipientId
                 contactsManager:(OWSContactsManager *)contactsManager
{
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
    self.contactsManager = contactsManager;

    NSString *threadName = thread.name;
    if (threadName.length == 0 && [thread isKindOfClass:[TSGroupThread class]]) {
        threadName = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }

    NSAttributedString *attributedText = [[NSAttributedString alloc]
                                          initWithString:threadName
                                          attributes:@{
                                                       NSForegroundColorAttributeName : [UIColor blackColor],
                                                       }];
    self.nameLabel.attributedText = attributedText;

    if ([thread isKindOfClass:[TSContactThread class]]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(otherUsersProfileDidChange:)
                                                     name:kNSNotificationName_OtherUsersProfileDidChange
                                                   object:nil];
        [self updateProfileName];
    }
    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread
                                                         diameter:kContactTableViewCellAvatarSize
                                                  contactsManager:contactsManager];

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
    OWSAssert([NSThread isMainThread]);

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssert(recipientId.length > 0);

    if (recipientId.length > 0 && [self.recipientId isEqualToString:recipientId]) {
        [self updateProfileName];
        [self updateAvatar];
    }
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
