//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ContactCellView.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionMessagingKit/OWSPrimaryStorage.h>
#import <SignalUtilitiesKit/SignalAccount.h>
#import <SessionMessagingKit/TSContactThread.h>
#import <SessionMessagingKit/TSGroupThread.h>
#import <SessionMessagingKit/TSThread.h>
#import <SessionUIKit/SessionUIKit.h>

NS_ASSUME_NONNULL_BEGIN

const CGFloat kContactCellAvatarTextMargin = 12;

@interface ContactCellView ()

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *profileNameLabel;
@property (nonatomic) LKProfilePictureView *profilePictureView;
@property (nonatomic) UILabel *subtitleLabel;
@property (nonatomic) UILabel *accessoryLabel;
@property (nonatomic) UIStackView *nameContainerView;
@property (nonatomic) UIView *accessoryViewContainer;

@property (nonatomic, nullable) TSThread *thread;
@property (nonatomic) NSString *recipientId;

@end

#pragma mark -

@implementation ContactCellView

- (instancetype)init
{
    if (self = [super init]) {
        [self configure];
    }
    return self;
}

#pragma mark - Dependencies

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

- (void)configure
{
    OWSAssertDebug(!self.nameLabel);

    self.layoutMargins = UIEdgeInsetsZero;

    _profilePictureView = [LKProfilePictureView new];
    CGFloat profilePictureSize = LKValues.mediumProfilePictureSize;
    [self.profilePictureView autoSetDimension:ALDimensionWidth toSize:profilePictureSize];
    [self.profilePictureView autoSetDimension:ALDimensionHeight toSize:profilePictureSize];
    self.profilePictureView.size = profilePictureSize;

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.profileNameLabel = [UILabel new];
    self.profileNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.subtitleLabel = [UILabel new];

    self.accessoryLabel = [[UILabel alloc] init];
    self.accessoryLabel.textAlignment = NSTextAlignmentRight;

    self.accessoryViewContainer = [UIView containerView];

    self.nameContainerView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.profileNameLabel,
        self.subtitleLabel,
    ]];
    self.nameContainerView.axis = UILayoutConstraintAxisVertical;

    [self.nameContainerView setContentHuggingHorizontalLow];
    [self.accessoryViewContainer setContentHuggingHorizontalHigh];

    self.axis = UILayoutConstraintAxisHorizontal;
    self.spacing = LKValues.mediumSpacing;
    self.alignment = UIStackViewAlignmentCenter;
    [self addArrangedSubview:self.profilePictureView];
    [self addArrangedSubview:self.nameContainerView];
    [self addArrangedSubview:self.accessoryViewContainer];

    [self configureFontsAndColors];
}

- (void)configureFontsAndColors
{
    self.nameLabel.font = [UIFont boldSystemFontOfSize:15];
    self.profileNameLabel.font = [UIFont ows_regularFontWithSize:11.f];
    self.subtitleLabel.font = [UIFont ows_regularFontWithSize:11.f];
    self.accessoryLabel.font = [UIFont ows_mediumFontWithSize:13.f];

    self.nameLabel.textColor = LKColors.text;
    self.profileNameLabel.textColor = LKColors.separator;
    self.subtitleLabel.textColor = LKColors.separator;
    self.accessoryLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
}

- (void)configureWithRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];

    self.recipientId = recipientId;

    [self.primaryStorage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        self.thread = [TSContactThread getThreadWithContactSessionID:recipientId transaction:transaction];
    }];

    BOOL isNoteToSelf = (IsNoteToSelfEnabled() && [recipientId isEqualToString:self.tsAccountManager.localNumber]);
    if (isNoteToSelf) {
        self.nameLabel.attributedText = [[NSAttributedString alloc]
            initWithString:NSLocalizedString(@"NOTE_TO_SELF", @"Label for 1:1 conversation with yourself.")
                attributes:@{
                    NSFontAttributeName : self.nameLabel.font,
                }];
    } else {
        SNContactContext context = [SNContact contextForThread:self.thread];
        self.nameLabel.text = [[LKStorage.shared getContactWithSessionID:recipientId] displayNameFor:context] ?: recipientId;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
    [self updateProfileName];
    [self updateAvatar];

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread
{
    OWSAssertDebug(thread);
    self.thread = thread;
    
    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];

    NSString *threadName = thread.name;
    if (threadName.length == 0 && [thread isKindOfClass:[TSGroupThread class]]) {
        threadName = [MessageStrings newGroupDefaultTitle];
    }

    BOOL isNoteToSelf
        = ([thread isKindOfClass:TSContactThread.class] && [((TSContactThread *)thread).contactSessionID isEqualToString:self.tsAccountManager.localNumber]);
    if (isNoteToSelf) {
        threadName = NSLocalizedString(@"NOTE_TO_SELF", @"Label for 1:1 conversation with yourself.");
    }

    if ([thread isKindOfClass:[TSContactThread class]]) {
        self.recipientId = ((TSContactThread *)thread).contactSessionID;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(otherUsersProfileDidChange:)
                                                     name:kNSNotificationName_OtherUsersProfileDidChange
                                                   object:nil];
        [self updateProfileName];
    } else {
        self.nameLabel.text = thread.name;
        [self.nameLabel setNeedsLayout];
    }
    
    [self updateAvatar];

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)updateAvatar
{
    [LKStorage readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [LKMentionsManager populateUserPublicKeyCacheIfNeededFor:self.thread.uniqueId in:transaction]; // FIXME: This is a terrible place to do this
    }];
    if (self.thread != nil) {
        [self.profilePictureView updateForThread:self.thread];
    } else {
        [self.profilePictureView updateForContact:self.recipientId];
    }
}

- (void)updateProfileName
{
    NSString *publicKey = self.recipientId;
    NSString *threadID = self.thread.uniqueId;
    SNContactContext context = [SNContact contextForThread:self.thread];
    NSString *displayName = [[LKStorage.shared getContactWithSessionID:publicKey] displayNameFor:context] ?: publicKey;
    self.nameLabel.text = displayName;
    [self.nameLabel setNeedsLayout];
}

- (void)prepareForReuse
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    self.thread = nil;
    self.accessoryMessage = nil;
    self.nameLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.profileNameLabel.text = nil;
    self.accessoryLabel.text = nil;
    for (UIView *subview in self.accessoryViewContainer.subviews) {
        [subview removeFromSuperview];
    }
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssertDebug(recipientId.length > 0);

    if (recipientId.length > 0 && [self.recipientId isEqualToString:recipientId]) {
        [self updateProfileName];
        [self updateAvatar];
    }
}

- (NSAttributedString *)verifiedSubtitle
{
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    // "checkmark"
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:@"\uf00c "
                                         attributes:@{
                                             NSFontAttributeName :
                                                 [UIFont ows_fontAwesomeFont:self.subtitleLabel.font.pointSize],
                                         }]];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                        @"Badge indicating that the user is verified.")]];
    return [text copy];
}

- (void)setAttributedSubtitle:(nullable NSAttributedString *)attributedSubtitle
{
    self.subtitleLabel.attributedText = attributedSubtitle;
}

- (BOOL)hasAccessoryText
{
    return self.accessoryMessage.length > 0;
}

- (void)setAccessoryView:(UIView *)accessoryView
{
    OWSAssertDebug(accessoryView);
    OWSAssertDebug(self.accessoryViewContainer);
    OWSAssertDebug(self.accessoryViewContainer.subviews.count < 1);

    [self.accessoryViewContainer addSubview:accessoryView];

    // Trailing-align the accessory view.
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeTop];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeBottom];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeTrailing];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeLeading relation:NSLayoutRelationGreaterThanOrEqual];
}

@end

NS_ASSUME_NONNULL_END
