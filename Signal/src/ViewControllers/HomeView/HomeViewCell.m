//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "HomeViewCell.h"
#import "OWSAvatarBuilder.h"
#import "Signal-Swift.h"
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/OWSMath.h>
#import <SignalMessaging/OWSUserProfile.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface HomeViewCell ()

@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UIStackView *payloadView;
@property (nonatomic) UIStackView *topRowView;
@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *snippetLabel;
@property (nonatomic) UILabel *dateTimeLabel;
// The unread badge has a larger v-height than the other elements in its
// row.  We don't want it to distort the v-alignment of the cell's labels
// so we use a placeholder to reserve the correct width.
@property (nonatomic) UIView *unreadPlaceholder;
@property (nonatomic) UIView *unreadBadge;
@property (nonatomic) UILabel *unreadLabel;

@property (nonatomic, nullable) TSThread *thread;
@property (nonatomic, nullable) OWSContactsManager *contactsManager;

@property (nonatomic, readonly) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@end

#pragma mark -

@implementation HomeViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self commontInit];
    }
    return self;
}

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }

    return self;
}

- (void)commontInit
{
    OWSAssert(!self.avatarView);

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.preservesSuperviewLayoutMargins = NO;
    self.contentView.preservesSuperviewLayoutMargins = NO;

    self.backgroundColor = [UIColor whiteColor];

    _viewConstraints = [NSMutableArray new];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];
    [self.avatarView autoPinLeadingToSuperviewMarginWithInset:self.cellHMargin];
    [self.avatarView autoVCenterInSuperview];
    [self.avatarView setContentHuggingHigh];
    [self.avatarView setCompressionResistanceHigh];

    self.payloadView = [UIStackView new];
    self.payloadView.axis = UILayoutConstraintAxisVertical;
    [self.contentView addSubview:self.payloadView];
    [self.payloadView autoPinLeadingToTrailingEdgeOfView:self.avatarView offset:self.avatarHSpacing];
    [self.payloadView autoPinTrailingToSuperviewMarginWithInset:self.cellHMargin];
    [self.payloadView autoVCenterInSuperview];
    // Ensure that the cell's contents never overflow the cell bounds.
    [self.payloadView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [self.payloadView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.font = self.nameFont;
    [self.nameLabel setContentHuggingHorizontalLow];
    [self.nameLabel setCompressionResistanceHorizontalLow];

    self.dateTimeLabel = [UILabel new];
    [self.dateTimeLabel setContentHuggingHorizontalHigh];
    [self.dateTimeLabel setCompressionResistanceHorizontalHigh];

    self.topRowView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.dateTimeLabel,
    ]];
    self.topRowView.axis = UILayoutConstraintAxisHorizontal;
    self.topRowView.alignment = UIStackViewAlignmentCenter;
    [self.payloadView addArrangedSubview:self.topRowView];

    self.snippetLabel = [UILabel new];
    self.snippetLabel.font = [self snippetFont];
    self.snippetLabel.numberOfLines = 1;
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.payloadView addArrangedSubview:self.snippetLabel];
    [self.snippetLabel setContentHuggingHorizontalLow];
    [self.snippetLabel setCompressionResistanceHorizontalLow];

    self.unreadLabel = [UILabel new];
    self.unreadLabel.font = [UIFont ows_dynamicTypeCaption1Font];
    self.unreadLabel.textColor = [UIColor whiteColor];
    self.unreadLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.unreadLabel.textAlignment = NSTextAlignmentCenter;

    self.unreadPlaceholder = [UIView containerView];
    [self.unreadPlaceholder setContentHuggingHigh];
    [self.unreadPlaceholder setCompressionResistanceHigh];

    self.unreadBadge = [NeverClearView new];
    self.unreadBadge.backgroundColor = [UIColor ows_materialBlueColor];
    [self.unreadPlaceholder addSubview:self.unreadBadge];
    [self.unreadBadge autoCenterInSuperview];
    [self.unreadBadge setContentHuggingHigh];
    [self.unreadBadge setCompressionResistanceHigh];

    [self.unreadBadge addSubview:self.unreadLabel];
    [self.unreadLabel autoVCenterInSuperview];
    [self.unreadLabel autoPinWidthToSuperview];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)initializeLayout
{
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (void)configureWithThread:(TSThread *)thread
              contactsManager:(OWSContactsManager *)contactsManager
        blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet
{
    OWSAssertIsOnMainThread();
    OWSAssert(thread);
    OWSAssert(contactsManager);
    OWSAssert(blockedPhoneNumberSet);

    self.thread = thread;
    self.contactsManager = contactsManager;

    BOOL hasUnreadMessages = thread.hasUnreadMessages;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
    [self updateNameLabel];
    [self updateAvatarView];

    self.payloadView.spacing = 0.f;
    self.topRowView.spacing = ceil([HomeViewCell scaleValueWithDynamicType:5]);

    // We update the fonts every time this cell is configured to ensure that
    // changes to the dynamic type settings are reflected.
    self.snippetLabel.font = [self snippetFont];
    self.snippetLabel.attributedText =
        [self attributedSnippetForThread:thread blockedPhoneNumberSet:blockedPhoneNumberSet];

    self.dateTimeLabel.attributedText = [self attributedStringForDate:thread.lastMessageDate];
    self.dateTimeLabel.textColor = hasUnreadMessages ? [UIColor ows_materialBlueColor] : [UIColor ows_darkGrayColor];

    NSUInteger unreadCount = [[OWSMessageUtils sharedManager] unreadMessagesInThread:thread];
    if (unreadCount > 0) {
        [self.topRowView addArrangedSubview:self.unreadPlaceholder];

        self.unreadLabel.font = [UIFont ows_dynamicTypeCaption1Font];
        self.unreadLabel.text = [OWSFormat formatInt:MIN(99, (int)unreadCount)];

        // TODO: Will this localize?  It assumes that the worst case
        // unread count (99) will fit horizontally into some multiple
        // N of the font's line height.
        const int unreadBadgeSize = (int)ceil(self.unreadLabel.font.lineHeight * 1.5f);
        self.unreadBadge.layer.cornerRadius = unreadBadgeSize / 2;

        [self.viewConstraints addObjectsFromArray:@[
            [self.unreadPlaceholder autoSetDimension:ALDimensionWidth toSize:unreadBadgeSize],
            [self.unreadBadge autoSetDimension:ALDimensionWidth toSize:unreadBadgeSize],
            [self.unreadBadge autoSetDimension:ALDimensionHeight toSize:unreadBadgeSize],
        ]];
    }
}

- (void)updateAvatarView
{
    OWSContactsManager *contactsManager = self.contactsManager;
    if (contactsManager == nil) {
        OWSFail(@"%@ contactsManager should not be nil", self.logTag);
        self.avatarView.image = nil;
        return;
    }

    TSThread *thread = self.thread;
    if (thread == nil) {
        OWSFail(@"%@ thread should not be nil", self.logTag);
        self.avatarView.image = nil;
        return;
    }

    self.avatarView.image =
        [OWSAvatarBuilder buildImageForThread:thread diameter:self.avatarSize contactsManager:contactsManager];
}

- (NSAttributedString *)attributedSnippetForThread:(TSThread *)thread
                             blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet
{
    OWSAssert(thread);

    BOOL isBlocked = NO;
    if (!thread.isGroupThread) {
        NSString *contactIdentifier = thread.contactIdentifier;
        isBlocked = [blockedPhoneNumberSet containsObject:contactIdentifier];
    }
    BOOL hasUnreadMessages = thread.hasUnreadMessages;

    NSMutableAttributedString *snippetText = [NSMutableAttributedString new];
    if (isBlocked) {
        // If thread is blocked, don't show a snippet or mute status.
        [snippetText
            appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:NSLocalizedString(@"HOME_VIEW_BLOCKED_CONTACT_CONVERSATION",
                                                          @"A label for conversations with blocked users.")
                                           attributes:@{
                                               NSFontAttributeName : self.snippetFont.ows_medium,
                                               NSForegroundColorAttributeName : [UIColor ows_blackColor],
                                           }]];
    } else {
        if ([thread isMuted]) {
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                    initWithString:@"\ue067  "
                                                        attributes:@{
                                                            NSFontAttributeName : [UIFont ows_elegantIconsFont:9.f],
                                                            NSForegroundColorAttributeName : (hasUnreadMessages
                                                                    ? [UIColor colorWithWhite:0.1f alpha:1.f]
                                                                    : [UIColor lightGrayColor]),
                                                        }]];
        }
        NSString *displayableText = thread.lastMessageLabel.filterStringForDisplay;
        if (displayableText) {
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                    initWithString:displayableText
                                                        attributes:@{
                                                            NSFontAttributeName :
                                                                (hasUnreadMessages ? self.snippetFont.ows_medium
                                                                                   : self.snippetFont),
                                                            NSForegroundColorAttributeName :
                                                                (hasUnreadMessages ? [UIColor ows_blackColor]
                                                                                   : [UIColor lightGrayColor]),
                                                        }]];
        }
    }

    return snippetText;
}

#pragma mark - Date formatting

- (NSAttributedString *)attributedStringForDate:(nullable NSDate *)date
{
    if (date == nil) {
        OWSProdLogAndFail(@"%@ date was unexpectedly nil", self.logTag);
        return [NSAttributedString new];
    }

    NSString *dateTimeString;
    if (![DateUtil dateIsThisYear:date]) {
        dateTimeString = [[DateUtil dateFormatter] stringFromDate:date];
    } else if ([DateUtil dateIsOlderThanOneWeek:date]) {
        dateTimeString = [[DateUtil monthAndDayFormatter] stringFromDate:date];
    } else if ([DateUtil dateIsOlderThanToday:date]) {
        dateTimeString = [[DateUtil shortDayOfWeekFormatter] stringFromDate:date];
    } else {
        dateTimeString = [[DateUtil timeFormatter] stringFromDate:date];
    }

    return [[NSAttributedString alloc] initWithString:dateTimeString.uppercaseString
                                           attributes:@{
                                               NSForegroundColorAttributeName : [UIColor blackColor],
                                               NSFontAttributeName : self.dateTimeFont,
                                           }];
}

#pragma mark - Constants

- (UIFont *)dateTimeFont
{
    return [UIFont ows_dynamicTypeFootnoteFont].ows_medium;
}

- (UIFont *)snippetFont
{
    return [UIFont ows_dynamicTypeFootnoteFont];
}

- (UIFont *)nameFont
{
    return [UIFont ows_dynamicTypeBodyFont].ows_medium;
}

// Used for profile names.
- (UIFont *)nameSecondaryFont
{
    return [UIFont ows_dynamicTypeFootnoteFont];
}

// A simple function to scale dimensions to reflect dynamic type.  Given a value
// we lerp it larger linearly to reflect size of dynamic type relative to a
// reference value for default dynamic type sizes.
//
// * We _NEVER_ scale values down.
// * We cap scaling.
+ (CGFloat)scaleValueWithDynamicType:(CGFloat)minValue
{
    // The default size of dynamic "body" type.
    const NSUInteger kReferenceFontSizeMin = 17.f;

    CGFloat referenceFontSize = UIFont.ows_dynamicTypeBodyFont.pointSize;
    CGFloat alpha = CGFloatClamp(referenceFontSize / kReferenceFontSizeMin, 1.f, 1.3f);
    return minValue * alpha;
}

+ (CGFloat)rowHeight
{
    // Scale the cell height using size of dynamic "body" type as a reference.
    const CGFloat kReferenceFontSizeMin = 17.f;
    const CGFloat kReferenceFontSizeMax = 23.f;
    CGFloat referenceFontSize = UIFont.ows_dynamicTypeBodyFont.pointSize;
    CGFloat alpha = CGFloatClamp01(CGFloatInverseLerp(referenceFontSize, kReferenceFontSizeMin, kReferenceFontSizeMax));

    const CGFloat kCellHeightMin = 68.f;
    const CGFloat kCellHeightMax = 76.f;
    CGFloat result = ceil(CGFloatLerp(kCellHeightMin, kCellHeightMax, alpha));

    return result;
}

- (NSUInteger)cellHMargin
{
    return 16;
}

- (NSUInteger)avatarSize
{
    return 48.f;
}

- (NSUInteger)avatarHSpacing
{
    return 12.f;
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    [self.viewConstraints removeAllObjects];

    self.thread = nil;
    self.contactsManager = nil;

    [self.unreadPlaceholder removeFromSuperview];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Name

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    if (recipientId.length == 0) {
        return;
    }

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        return;
    }

    if (![self.thread.contactIdentifier isEqualToString:recipientId]) {
        return;
    }

    [self updateNameLabel];
    [self updateAvatarView];
}

- (void)updateNameLabel
{
    OWSAssertIsOnMainThread();

    self.nameLabel.font = self.nameFont;

    TSThread *thread = self.thread;
    if (thread == nil) {
        OWSFail(@"%@ thread should not be nil", self.logTag);
        self.nameLabel.attributedText = nil;
        return;
    }

    OWSContactsManager *contactsManager = self.contactsManager;
    if (contactsManager == nil) {
        OWSFail(@"%@ contacts manager should not be nil", self.logTag);
        self.nameLabel.attributedText = nil;
        return;
    }

    NSAttributedString *name;
    if (thread.isGroupThread) {
        if (thread.name.length == 0) {
            name = [[NSAttributedString alloc] initWithString:[MessageStrings newGroupDefaultTitle]];
        } else {
            name = [[NSAttributedString alloc] initWithString:thread.name];
        }
    } else {
        name = [contactsManager attributedStringForConversationTitleWithPhoneIdentifier:thread.contactIdentifier
                                                                            primaryFont:self.nameFont
                                                                          secondaryFont:self.nameSecondaryFont];
    }

    self.nameLabel.attributedText = name;
}

@end

NS_ASSUME_NONNULL_END
