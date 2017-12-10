//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "InboxTableViewCell.h"
#import "OWSAvatarBuilder.h"
#import "Signal-Swift.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/OWSUserProfile.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kAvatarViewDiameter = 44;

@interface InboxTableViewCell ()

@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *snippetLabel;
@property (nonatomic) UILabel *dummyLabel;
@property (nonatomic) UILabel *timeLabel;
@property (nonatomic) UIView *unreadBadge;
@property (nonatomic) UILabel *unreadLabel;

@property (nonatomic) TSThread *thread;
@property (nonatomic) OWSContactsManager *contactsManager;

@property NSLayoutConstraint *nAvatarWidth;
@property NSLayoutConstraint *nNameLeading;
@property NSLayoutConstraint *nNameTop;
@property NSLayoutConstraint *nTimeLeading;
@property NSLayoutConstraint *nTimeTrailing;
@property NSLayoutConstraint *nTimeTop;
@property NSLayoutConstraint *nTimeBottom;
@property NSLayoutConstraint *nTimeCenter;
@property NSLayoutConstraint *nSnippetBottom;
@property NSLayoutConstraint *nDummyLeading;
@property NSLayoutConstraint *nDummyTrailing;
@property NSLayoutConstraint *nDummyTop;
@property NSLayoutConstraint *nDummyBottom;

@property NSLayoutConstraint *aAvatarWidth;
@property NSLayoutConstraint *aNameLeading;
@property NSLayoutConstraint *aNameTop;
@property NSLayoutConstraint *aNameTrailing;
@property NSLayoutConstraint *aTimeLeading;
@property NSLayoutConstraint *aTimeTrailing;
@property NSLayoutConstraint *aTimeTop;
@property NSLayoutConstraint *aTimeBottom;
@property NSLayoutConstraint *aSnippetBottom;

@property bool accessibilityMode;

@end

#pragma mark -

@implementation InboxTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self commonInit];
    }
    return self;
}

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commonInit];
    }

    return self;
}

- (void)commonInit
{
    OWSAssert(!self.avatarView);

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    self.backgroundColor = [UIColor whiteColor];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.contentView addSubview:self.nameLabel];
    [self.nameLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.snippetLabel = [UILabel new];
    self.snippetLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.snippetLabel.textColor = [UIColor grayColor];
    self.snippetLabel.numberOfLines = 2;
    [self.contentView addSubview:self.snippetLabel];
    [self.snippetLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.dummyLabel = [UILabel new];
    self.dummyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.dummyLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.dummyLabel.numberOfLines = 2;
    self.dummyLabel.text = @"\n";
    self.dummyLabel.hidden = YES;
    [self.contentView addSubview:self.dummyLabel];
    [self.dummyLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.timeLabel = [UILabel new];
    self.timeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [self.contentView addSubview:self.timeLabel];
    [self.timeLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.unreadBadge = [UIView new];
    [self.unreadBadge setBackgroundColor:[UIColor ows_materialBlueColor]];
    [self.contentView addSubview:self.unreadBadge];
    [self.unreadBadge setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.unreadLabel = [UILabel new];
    self.unreadLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.unreadLabel.textColor = [UIColor whiteColor];
    self.unreadLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.unreadLabel.textAlignment = NSTextAlignmentCenter;
    [self.unreadBadge addSubview:self.unreadLabel];
    self.unreadLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.unreadLabel autoVCenterInSuperview];
    [self.unreadLabel autoPinWidthToSuperview];

    [self addSharedConstraints];
    [self addNormalConstraints];
    [self addAccessibilityConstraints];
}

#pragma mark - Dynamic layout

- (void)addSharedConstraints
{
    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;

    [self.avatarView.heightAnchor constraintEqualToConstant:kAvatarViewDiameter].active = YES;
    [self.avatarView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor].active = YES;
    [self.avatarView.centerYAnchor constraintEqualToAnchor:margins.centerYAnchor].active = YES;

    [self.nameLabel setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisVertical];
    [self.nameLabel setContentCompressionResistancePriority:1000 forAxis:UILayoutConstraintAxisVertical];

    [self.snippetLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor].active = YES;
    [self.snippetLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2.0].active = YES;
    [self.snippetLabel setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisVertical];

    [self.dummyLabel setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisVertical];

    [self.timeLabel setContentHuggingPriority:500 forAxis:UILayoutConstraintAxisHorizontal];
    [self.timeLabel setContentCompressionResistancePriority:1000 forAxis:UILayoutConstraintAxisHorizontal];

    [self.unreadBadge.widthAnchor constraintEqualToAnchor:self.unreadLabel.heightAnchor constant:6.0].active = YES;
    [self.unreadBadge.heightAnchor constraintEqualToAnchor:self.unreadLabel.heightAnchor constant:6.0].active = YES;
    [self.unreadBadge.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.snippetLabel.trailingAnchor constant:4.0].active = YES;
    [self.unreadBadge.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor].active = YES;
    [self.unreadBadge.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2.0].active = YES;
    [self.unreadBadge.bottomAnchor constraintLessThanOrEqualToAnchor:margins.bottomAnchor].active = YES;
    [self.unreadLabel setContentCompressionResistancePriority:1000 forAxis:UILayoutConstraintAxisHorizontal];
    [self.unreadLabel setContentCompressionResistancePriority:1000 forAxis:UILayoutConstraintAxisVertical];
}

- (void)addNormalConstraints
{
    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;

    self.nAvatarWidth = [self.avatarView.widthAnchor constraintEqualToConstant:kAvatarViewDiameter];
    self.nNameLeading = [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:16.0];
    self.nNameTop = [self.nameLabel.topAnchor constraintEqualToAnchor:margins.topAnchor];
    self.nTimeLeading = [self.timeLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor constant:4.0];
    self.nTimeTrailing = [self.timeLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor];
    self.nTimeTop = [self.timeLabel.topAnchor constraintGreaterThanOrEqualToAnchor:margins.topAnchor];
    self.nTimeBottom = [self.timeLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.snippetLabel.topAnchor];
    self.nTimeCenter = [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.nameLabel.centerYAnchor];
    self.nSnippetBottom = [self.snippetLabel.bottomAnchor constraintLessThanOrEqualToAnchor:margins.bottomAnchor];
    self.nDummyLeading = [self.dummyLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor];
    self.nDummyTrailing = [self.dummyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:margins.trailingAnchor];
    self.nDummyTop = [self.dummyLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2.0];
    self.nDummyBottom = [self.dummyLabel.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor];
}

- (void)addAccessibilityConstraints
{
    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;

    self.aAvatarWidth = [self.avatarView.widthAnchor constraintEqualToConstant:0];
    self.aNameLeading = [self.nameLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor];
    self.aNameTop = [self.nameLabel.topAnchor constraintEqualToAnchor:margins.topAnchor constant:-12.0];
    self.aNameTrailing = [self.nameLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor];
    self.aTimeLeading = [self.timeLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor];
    self.aTimeTrailing = [self.timeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.unreadBadge.leadingAnchor constant:-4.0];
    self.aTimeTop = [self.timeLabel.topAnchor constraintEqualToAnchor:self.snippetLabel.bottomAnchor constant:2.0];
    self.aTimeBottom = [self.timeLabel.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:12.0];
}

- (void)enableAccessibilityLayout:(bool)accessibility
{
    self.accessibilityMode = accessibility;

    self.nAvatarWidth.active = !accessibility;
    self.nNameLeading.active = !accessibility;
    self.nNameTop.active = !accessibility;
    self.nTimeLeading.active = !accessibility;
    self.nTimeTrailing.active = !accessibility;
    self.nTimeTop.active = !accessibility;
    self.nTimeBottom.active = !accessibility;
    self.nTimeCenter.active = !accessibility;
    self.nSnippetBottom.active = !accessibility;
    self.nDummyLeading.active = !accessibility;
    self.nDummyTrailing.active = !accessibility;
    self.nDummyTop.active = !accessibility;
    self.nDummyBottom.active = !accessibility;

    self.aAvatarWidth.active = accessibility;
    self.aNameLeading.active = accessibility;
    self.aNameTop.active = accessibility;
    self.aNameTrailing.active = accessibility;
    self.aTimeLeading.active = accessibility;
    self.aTimeTrailing.active = accessibility;
    self.aTimeTop.active = accessibility;
    self.aTimeBottom.active = accessibility;

    self.nameLabel.numberOfLines = accessibility ? 2 : 1;
    self.timeLabel.textColor = accessibility ? [UIColor blackColor] : [UIColor grayColor];
}

- (void)updateFonts
{
    self.nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.snippetLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.dummyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.timeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.unreadLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];

    NSString *category = [[UIApplication sharedApplication] preferredContentSizeCategory];
    [self enableAccessibilityLayout:[self isAccessibilityCategory:category]];
}

- (bool)isAccessibilityCategory:(NSString *)category
{
    return [category isEqualToString:UIContentSizeCategoryAccessibilityMedium]
        || [category isEqualToString:UIContentSizeCategoryAccessibilityLarge]
        || [category isEqualToString:UIContentSizeCategoryAccessibilityExtraLarge]
        || [category isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraLarge]
        || [category isEqualToString:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.unreadBadge.layer.cornerRadius = self.unreadBadge.frame.size.width / 2;
}

#pragma mark -

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)initializeLayout {
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
    OWSAssert([NSThread isMainThread]);
    OWSAssert(thread);
    OWSAssert(contactsManager);
    OWSAssert(blockedPhoneNumberSet);

    self.thread = thread;
    self.contactsManager = contactsManager;
    
    BOOL isBlocked = NO;
    if (!thread.isGroupThread) {
        NSString *contactIdentifier = thread.contactIdentifier;
        isBlocked = [blockedPhoneNumberSet containsObject:contactIdentifier];
    }
    
    NSMutableAttributedString *snippetText = [NSMutableAttributedString new];
    if (isBlocked) {
        // If thread is blocked, don't show a snippet or mute status.
        [snippetText appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"HOME_VIEW_BLOCKED_CONTACT_CONVERSATION",
                                                                                                         @"A label for conversations with blocked users.")
                                                                            attributes:@{
                                                                                         NSForegroundColorAttributeName : [UIColor blackColor],
                                                                                         }]];
        UIFont *subheadFont = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        UIFontDescriptor *boldDescriptor = [[subheadFont fontDescriptor] fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
        UIFont *boldFont = [UIFont fontWithDescriptor:boldDescriptor size:0];
        self.snippetLabel.font = boldFont;
    } else {
        if ([thread isMuted]) {
            UIFont *font = [UIFont ows_elegantIconsFont:13];
            UIFont *dynamicFont;
            if (@available(iOS 11.0, *)) {
                UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline];
                dynamicFont = [metrics scaledFontForFont:font];
            } else {
                // Fallback on earlier versions
                dynamicFont = font;
            }
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:@"\ue067  "
                                                 attributes:@{
                                                              NSFontAttributeName:dynamicFont
                                                              }]];
        }
        NSString *displayableText = [DisplayableText displayableText:thread.lastMessageLabel];
        if (displayableText) {
            [snippetText appendAttributedString:[[NSAttributedString alloc] initWithString:displayableText]];
        }
    }

    NSAttributedString *attributedDate = [self dateAttributedString:thread.lastMessageDate];
    NSUInteger unreadCount = [[OWSMessageManager sharedManager] unreadMessagesInThread:thread];


    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
    [self updateNameLabel];
    [self updateAvatarView];

    self.snippetLabel.attributedText = snippetText;
    self.timeLabel.attributedText = attributedDate;

    if (self.accessibilityMode) {
        self.separatorInset = UIEdgeInsetsMake(0, 0, 0, 0);
    } else {
        self.separatorInset = UIEdgeInsetsMake(0, self.contentView.layoutMargins.left, 0, 0);
    }

    if (thread.hasUnreadMessages) {
        self.timeLabel.textColor = [UIColor ows_materialBlueColor];
    } else if (self.accessibilityMode) {
        self.timeLabel.textColor = [UIColor blackColor];
    } else {
        self.timeLabel.textColor = [UIColor grayColor];
    }

    if (unreadCount > 0) {
        self.unreadBadge.hidden = NO;
        self.unreadLabel.hidden = NO;
        self.unreadLabel.text = [OWSFormat formatInt:MIN(99, (int)unreadCount)];
    } else {
        self.unreadBadge.hidden = YES;
        self.unreadLabel.hidden = YES;
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
        [OWSAvatarBuilder buildImageForThread:thread diameter:kAvatarViewDiameter contactsManager:contactsManager];
}

#pragma mark - Date formatting

- (NSAttributedString *)dateAttributedString:(NSDate *)date {
    NSString *timeString;

    if ([DateUtil dateIsToday:date]) {
        timeString = [[DateUtil timeFormatter] stringFromDate:date];
    } else {
        timeString = [[DateUtil dateFormatter] stringFromDate:date];
    }

    return [[NSMutableAttributedString alloc] initWithString:timeString];
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Name

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);
    
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

-(void)updateNameLabel
{
    AssertIsOnMainThread();
    
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
                                                                            primaryFont:self.nameLabel.font
                                                                          secondaryFont:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]];
    }
    
    self.nameLabel.attributedText = name;
}

@end

NS_ASSUME_NONNULL_END
