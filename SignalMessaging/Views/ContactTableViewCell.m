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
@property (nonatomic) UILabel *ows_accessoryView;
@property (nonatomic) UIStackView *nameContainerView;
//@property (nonatomic) UIView *nameContainerView;

@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) NSString *recipientId;

@end

#pragma mark -

@implementation ContactTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self configureWithContentView:self.contentView];
    }
    return self;
}

- (instancetype)initWithCustomContentView:(UIView *)customContentView
{
    if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ContactTableViewCell.reuseIdentifier]) {
        OWSAssert(customContentView);

        [self configureWithContentView:customContentView];
    }
    return self;
}

+ (NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (void)setAccessoryView:(nullable UIView *)accessoryView
{
    OWSFail(@"%@ don't use accessory view for this view.", self.logTag);
}

- (void)configureWithContentView:(UIView *)contentView
{
    //    self.preservesSuperviewLayoutMargins = YES;
    //    self.contentView.preservesSuperviewLayoutMargins = YES;
    //
    OWSAssert(!self.nameLabel);

    //    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    //    self.translatesAutoresizingMaskIntoConstraints = YES;
    //    self.contentView.translatesAutoresizingMaskIntoConstraints = YES;
    //    self.translatesAutoresizingMaskIntoConstraints = NO;
    //    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;

    _avatarView = [AvatarImageView new];
    [_avatarView autoSetDimension:ALDimensionWidth toSize:kContactTableViewCellAvatarSize];
    [_avatarView autoSetDimension:ALDimensionHeight toSize:kContactTableViewCellAvatarSize];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.textColor = [UIColor blackColor];

    self.profileNameLabel = [UILabel new];
    self.profileNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.profileNameLabel.textColor = [UIColor grayColor];

    self.subtitle = [UILabel new];
    self.subtitle.textColor = [UIColor ows_darkGrayColor];

    self.ows_accessoryView = [[UILabel alloc] init];
    self.ows_accessoryView.textAlignment = NSTextAlignmentRight;
    self.ows_accessoryView.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];

    //    self.nameContainerView = self.nameLabel;

    //    self.nameContainerView = [UIView containerView];
    //    [self.nameContainerView addSubview:self.nameLabel];
    //    [self.nameContainerView addSubview:self.profileNameLabel];
    //    [self.nameContainerView addSubview:self.subtitle];
    //    [self.nameLabel autoPinWidthToSuperview];
    //    [self.profileNameLabel autoPinWidthToSuperview];
    //    [self.subtitle autoPinWidthToSuperview];
    //    [self.nameLabel autoPinTopToSuperviewMargin];
    //    [self.profileNameLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.nameLabel];
    //    [self.subtitle autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.profileNameLabel];
    //    [self.subtitle autoPinBottomToSuperviewMargin];
    //
    //    [contentView addSubview:self.avatarView];
    //    [contentView addSubview:self.nameContainerView];
    //    [contentView addSubview:self.ows_accessoryView];
    //
    //    [self.avatarView autoVCenterInSuperview];
    //    [self.nameContainerView autoVCenterInSuperview];
    //    [self.ows_accessoryView autoVCenterInSuperview];
    //    [self.avatarView autoPinLeadingToSuperviewMargin];
    //    [self.nameContainerView autoPinLeadingToTrailingEdgeOfView:self.avatarView
    //    offset:kContactTableViewCellAvatarTextMargin];
    ////    [self.nameContainerView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    ////    [self.nameContainerView autoPinTrailingToSuperviewMargin];
    //    [self.ows_accessoryView autoPinLeadingToTrailingEdgeOfView:self.nameContainerView
    //    offset:kContactTableViewCellAvatarTextMargin]; [self.ows_accessoryView autoPinTrailingToSuperviewMargin];
    //    // Ensure that the cell's contents never overflow the cell bounds.
    //    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    //    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    //    [self.nameContainerView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    //    [self.nameContainerView autoPinEdgeToSuperviewMargin:ALEdgeBottom
    //    relation:NSLayoutRelationGreaterThanOrEqual]; [self.ows_accessoryView autoPinEdgeToSuperviewMargin:ALEdgeTop
    //    relation:NSLayoutRelationGreaterThanOrEqual]; [self.ows_accessoryView
    //    autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];

    //
    ////    UIView h = [UIView containerView];
    ////    [self.nameContainerView addSubview:self.nameLabel];
    ////    [self.nameContainerView addSubview:self.profileNameLabel];
    ////    [self.nameContainerView addSubview:self.subtitle];
    ////    [self.nameLabel autoPinWidthToSuperview];
    ////    [self.profileNameLabel autoPinWidthToSuperview];
    ////    [self.subtitle autoPinWidthToSuperview];
    ////    [self.nameLabel autoPinTopToSuperviewMargin];
    ////    [self.profileNameLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.nameLabel];
    ////    [self.subtitle autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.profileNameLabel];
    ////    [self.subtitle autoPinBottomToSuperviewMargin];
    //

    self.nameContainerView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.profileNameLabel,
        self.subtitle,
    ]];
    self.nameContainerView.axis = UILayoutConstraintAxisVertical;
    self.nameContainerView.alignment = UIStackViewAlignmentFill;
    //    hStackView.distribution = UIStackViewDistributionFill;
    //    [self.contentView addSubview:hStackView];
    //    [hStackView autoVCenterInSuperview];
    //    [hStackView autoPinLeadingToSuperviewMargin];
    //    [hStackView autoPinTrailingToSuperviewMargin];
    //    // Ensure that the cell's contents never overflow the cell bounds.
    //    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    //    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    //
    //
    ////    [self.avatarView setContentHuggingHorizontalHigh];
    ////    [self.nameLabel setContentHuggingHorizontalLow];
    ////    [self.profileNameLabel setContentHuggingHorizontalLow];
    ////    [self.subtitle setContentHuggingHorizontalLow];
    ////    [self.nameContainerView setContentHuggingHorizontalLow];
    //
    //    [self.ows_accessoryView setContentHuggingHorizontalLow];
    //
    ////    UIView *hStackView = [UIView new];
    ////    hStackView.backgroundColor = UIColor.greenColor;
    ////    [self.contentView addSubview:hStackView];
    ////    [hStackView autoPinToSuperviewEdges];
    ////    [hStackView setContentHuggingLow];
    //
    ////    [hStackView autoVCenterInSuperview];
    ////    [hStackView autoPinLeadingToSuperviewMargin];
    ////    //    [hStackView autoPinTrailingToSuperviewMargin];
    ////    [hStackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    ////    // Ensure that the cell's contents never overflow the cell bounds.
    ////    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    ////    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    ////    [hStackView setContentHuggingHorizontalLow];
    //
    UIStackView *hStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.avatarView,
        self.nameContainerView,
        self.ows_accessoryView,
    ]];
    hStackView.axis = UILayoutConstraintAxisHorizontal;
    hStackView.spacing = kContactTableViewCellAvatarTextMargin;
    hStackView.distribution = UIStackViewDistributionFill;
    [contentView addSubview:hStackView];
    [hStackView autoVCenterInSuperview];
    [hStackView autoPinLeadingToSuperviewMargin];
    [hStackView autoPinTrailingToSuperviewMargin];
    //    [hStackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    // Ensure that the cell's contents never overflow the cell bounds.
    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    //    [hStackView setContentHuggingHorizontalLow];
    //    [hStackView setCompressionResistanceHorizontalLow];
    //    [hStackView addBackgroundViewWithBackgroundColor:[UIColor greenColor]];
    //    [self.nameContainerView addBackgroundViewWithBackgroundColor:[UIColor blueColor]];

    [self configureFonts];

    //    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    //    [self layoutSubviews];
    //
    //    [self logFrameLaterWithLabel:@"cell"];
    //    [self.contentView logFrameLaterWithLabel:@"contentView"];
    //    [self.avatarView logFrameLaterWithLabel:@"avatarView"];
    //    [self.nameContainerView logFrameLaterWithLabel:@"nameContainerView"];
}

- (void)configureFonts
{
    self.nameLabel.font = [UIFont ows_dynamicTypeBodyFont];
    self.profileNameLabel.font = [UIFont ows_regularFontWithSize:11.f];
    self.subtitle.font = [UIFont ows_regularFontWithSize:11.f];
    self.ows_accessoryView.font = [UIFont ows_mediumFontWithSize:13.f];
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
        self.ows_accessoryView.text = self.accessoryMessage;
    }

    // Force layout, since imageView isn't being initally rendered on App Store optimized build.
    [self layoutSubviews];

    DDLogVerbose(@"%@ nameLabel size: %@, %@",
        self.logTag,
        NSStringFromCGSize([self.nameLabel sizeThatFits:CGSizeZero]),
        NSStringFromCGSize([self.nameLabel intrinsicContentSize]));
    DDLogVerbose(@"%@ nameContainerView size: %@, %@",
        self.logTag,
        NSStringFromCGSize([self.nameContainerView sizeThatFits:CGSizeZero]),
        NSStringFromCGSize([self.nameContainerView intrinsicContentSize]));
    DDLogVerbose(@"%@ ows_accessoryView size: %@, %@",
        self.logTag,
        NSStringFromCGSize([self.ows_accessoryView sizeThatFits:CGSizeZero]),
        NSStringFromCGSize([self.ows_accessoryView intrinsicContentSize]));
    DDLogVerbose(@"%@ contentView size: %@, %@",
        self.logTag,
        NSStringFromCGSize([self.contentView sizeThatFits:CGSizeZero]),
        NSStringFromCGSize([self.contentView intrinsicContentSize]));

    //    [self.nameLabel sizeToFit];
    //    [self.nameLabel autoSetDimension:ALDimensionWidth toSize:self.nameLabel.width];
    //    [self.nameLabel autoSetDimension:ALDimensionHeight toSize:self.nameLabel.height];

    //    [self.nameContainerView sizeToFit];
    //    [self.nameContainerView.superview sizeToFit];
    //    [self.nameContainerView logFrameWithLabel:@"nameContainerView?"];

    [self logFrameLaterWithLabel:@"cell"];
    [self.contentView logFrameLaterWithLabel:@"contentView"];
    [self.avatarView logFrameLaterWithLabel:@"avatarView"];
    [self.nameContainerView logFrameLaterWithLabel:@"nameContainerView"];
    [self.ows_accessoryView logFrameLaterWithLabel:@"ows_accessoryView"];
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
        self.ows_accessoryView.text = self.accessoryMessage;
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
    self.ows_accessoryView.text = nil;
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
