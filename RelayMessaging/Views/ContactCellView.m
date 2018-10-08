//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactCellView.h"
#import "OWSContactAvatarBuilder.h"
//#import "OWSContactsManager.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <RelayMessaging/RelayMessaging-Swift.h>
#import <RelayServiceKit/SignalAccount.h>
#import <RelayServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kContactCellAvatarSize = 48;
const CGFloat kContactCellAvatarTextMargin = 12;

@interface ContactCellView ()

@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *profileNameLabel;
@property (nonatomic) UIImageView *avatarView;
@property (nonatomic) UILabel *subtitleLabel;
@property (nonatomic) UILabel *accessoryLabel;
@property (nonatomic) UIStackView *nameContainerView;
@property (nonatomic) UIView *accessoryViewContainer;

@property (nonatomic) FLContactsManager *contactsManager;
@property (nonatomic, nullable) TSThread *thread;
@property (nonatomic, nullable) NSString *recipientId;
@property (nonatomic, nullable) NSString *tagId;

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

- (void)configure
{
    OWSAssert(!self.nameLabel);

    self.layoutMargins = UIEdgeInsetsZero;

    _avatarView = [AvatarImageView new];
    [_avatarView autoSetDimension:ALDimensionWidth toSize:kContactCellAvatarSize];
    [_avatarView autoSetDimension:ALDimensionHeight toSize:kContactCellAvatarSize];

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

    [self.avatarView setContentHuggingHorizontalHigh];
    [self.nameContainerView setContentHuggingHorizontalLow];
    [self.accessoryViewContainer setContentHuggingHorizontalHigh];

    self.axis = UILayoutConstraintAxisHorizontal;
    self.spacing = kContactCellAvatarTextMargin;
    self.alignment = UIStackViewAlignmentCenter;
    [self addArrangedSubview:self.avatarView];
    [self addArrangedSubview:self.nameContainerView];
    [self addArrangedSubview:self.accessoryViewContainer];

    [self configureFontsAndColors];
}

- (void)configureFontsAndColors
{
    self.nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    self.profileNameLabel.font = [UIFont ows_regularFontWithSize:11.f];
    self.subtitleLabel.font = [UIFont ows_regularFontWithSize:11.f];
    self.accessoryLabel.font = [UIFont ows_mediumFontWithSize:13.f];

    self.nameLabel.textColor = [Theme primaryColor];
    self.profileNameLabel.textColor = [Theme secondaryColor];
    self.subtitleLabel.textColor = [Theme secondaryColor];
    self.accessoryLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
}

- (void)configureWithTagId:(NSString *)tagId contactsManager:(FLContactsManager *)contactsManager
{
    OWSAssert(tagId.length > 0);
    OWSAssert(contactsManager);
    
    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];
    
    self.tagId = tagId;
    self.contactsManager = contactsManager;
    
    self.nameLabel.attributedText =
    [contactsManager formattedDisplayNameForTagId:tagId font:self.nameLabel.font];
    
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

- (void)configureWithRecipientId:(NSString *)recipientId contactsManager:(FLContactsManager *)contactsManager
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(contactsManager);

    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];

    self.recipientId = recipientId;
    self.contactsManager = contactsManager;

    if ([recipientId isEqualToString:[TSAccountManager localUID]]) {
        self.nameLabel.attributedText = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"ME_STRING", @"")
                                                                        attributes:@{ NSFontAttributeName : self.nameLabel.font }];
    } else {
        self.nameLabel.attributedText =
        [contactsManager formattedFullNameForRecipientId:recipientId font:self.nameLabel.font];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(otherUsersProfileDidChange:)
                                                     name:kNSNotificationName_OtherUsersProfileDidChange
                                                   object:nil];
    }
    [self updateProfileName];
    [self updateAvatar];

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)configureWithThread:(TSThread *)thread contactsManager:(FLContactsManager *)contactsManager
{
    OWSAssert(thread);
    self.thread = thread;
    
    // Update fonts to reflect changes to dynamic type.
    [self configureFontsAndColors];

    self.contactsManager = contactsManager;

    NSString *threadName = nil;
    if (thread.title.length > 0) {
        threadName = thread.title;
    } else if (thread.prettyExpression.length > 0) {
        threadName = thread.prettyExpression;
    } else {
        threadName = [MessageStrings newGroupDefaultTitle];
    }

    NSAttributedString *attributedText =
        [[NSAttributedString alloc] initWithString:threadName
                                        attributes:@{
                                            NSForegroundColorAttributeName : [Theme primaryColor],
                                        }];
    self.nameLabel.attributedText = attributedText;

//    if ([thread isKindOfClass:[TSThread class]]) {
//        self.recipientId = thread.contactIdentifier;
//
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(otherUsersProfileDidChange:)
//                                                     name:kNSNotificationName_OtherUsersProfileDidChange
//                                                   object:nil];
//        [self updateProfileName];
//    }
    
    self.avatarView.image =
        [OWSAvatarBuilder buildImageForThread:thread diameter:kContactCellAvatarSize contactsManager:contactsManager];

    if (self.accessoryMessage) {
        self.accessoryLabel.text = self.accessoryMessage;
        [self setAccessoryView:self.accessoryLabel];
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];
}

- (void)updateAvatar
{
    FLContactsManager *contactsManager = self.contactsManager;
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

    UIColor *color = [Theme conversationColorForString:self.recipientId];
    
    self.avatarView.image = [[[OWSContactAvatarBuilder alloc] initWithSignalId:recipientId
                                                                         color:color
                                                                      diameter:kContactCellAvatarSize
                                                               contactsManager:FLContactsManager.shared] build];
}

- (void)updateProfileName
{
    FLContactsManager *contactsManager = self.contactsManager;
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

    self.profileNameLabel.text = [contactsManager recipientWithId:recipientId].flTag.orgSlug;
    
    [self.profileNameLabel setNeedsLayout];
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
    OWSAssert(recipientId.length > 0);

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
    OWSAssert(accessoryView);
    OWSAssert(self.accessoryViewContainer);
    OWSAssert(self.accessoryViewContainer.subviews.count < 1);

    [self.accessoryViewContainer addSubview:accessoryView];

    // Trailing-align the accessory view.
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeTop];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeBottom];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeTrailing];
    [accessoryView autoPinEdgeToSuperviewMargin:ALEdgeLeading relation:NSLayoutRelationGreaterThanOrEqual];
}

@end

NS_ASSUME_NONNULL_END
