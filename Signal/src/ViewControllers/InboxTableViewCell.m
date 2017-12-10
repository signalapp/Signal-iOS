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

#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 11
#define DATE_LABEL_SIZE 13
#define SWIPE_ARCHIVE_OFFSET -50

const NSUInteger kAvatarViewDiameter = 52;

@interface InboxTableViewCell ()

@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *snippetLabel;
@property (nonatomic) UILabel *timeLabel;
@property (nonatomic) UIView *unreadBadge;
@property (nonatomic) UILabel *unreadLabel;

@property (nonatomic) TSThread *thread;
@property (nonatomic) OWSContactsManager *contactsManager;

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

    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;

    self.backgroundColor = [UIColor whiteColor];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.avatarView.widthAnchor constraintEqualToConstant:kAvatarViewDiameter].active = YES;
    [self.avatarView.heightAnchor constraintEqualToConstant:kAvatarViewDiameter].active = YES;
    [self.avatarView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor].active = YES;
    [self.avatarView.centerYAnchor constraintEqualToAnchor:margins.centerYAnchor].active = YES;

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.font = [UIFont ows_boldFontWithSize:14.0f];
    [self.contentView addSubview:self.nameLabel];
    [self.nameLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:16.0].active = YES;
    [self.nameLabel.topAnchor constraintEqualToAnchor:margins.topAnchor].active = YES;
    [self.nameLabel setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisVertical];
    [self.nameLabel setContentCompressionResistancePriority:1000 forAxis:UILayoutConstraintAxisVertical];

    self.snippetLabel = [UILabel new];
    self.snippetLabel.font = [UIFont ows_regularFontWithSize:14.f];
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.snippetLabel.textColor = [UIColor colorWithWhite:2 / 3.f alpha:1.f];
    self.snippetLabel.numberOfLines = 2;
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.snippetLabel];
    [self.snippetLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.snippetLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor].active = YES;
    [self.snippetLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2.0].active = YES;
    [self.snippetLabel.bottomAnchor constraintLessThanOrEqualToAnchor:margins.bottomAnchor].active = YES;
    [self.snippetLabel setContentHuggingPriority:1000 forAxis:UILayoutConstraintAxisVertical];

    self.timeLabel = [UILabel new];
    self.timeLabel.font = [UIFont ows_lightFontWithSize:14.f];
    [self.contentView addSubview:self.timeLabel];
    [self.timeLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.timeLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor constant:4.0].active = YES;
    [self.timeLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor].active = YES;
    [self.timeLabel.topAnchor constraintGreaterThanOrEqualToAnchor:margins.topAnchor].active = YES;
    [self.timeLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.snippetLabel.topAnchor].active = YES;
    [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.nameLabel.centerYAnchor].active = YES;
    [self.timeLabel setContentHuggingPriority:500 forAxis:UILayoutConstraintAxisHorizontal];
    [self.timeLabel setContentCompressionResistancePriority:1000 forAxis:UILayoutConstraintAxisHorizontal];

    const int kunreadBadgeSize = 24;
    self.unreadBadge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kunreadBadgeSize, kunreadBadgeSize)];
    self.unreadBadge.layer.cornerRadius = kunreadBadgeSize / 2;
    [self.unreadBadge setBackgroundColor:[UIColor ows_materialBlueColor]];
    [self.contentView addSubview:self.unreadBadge];
    [self.unreadBadge setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.unreadBadge.widthAnchor constraintEqualToConstant:kunreadBadgeSize].active = YES;
    [self.unreadBadge.heightAnchor constraintEqualToConstant:kunreadBadgeSize].active = YES;
    [self.unreadBadge.leadingAnchor constraintEqualToAnchor:self.snippetLabel.trailingAnchor constant:4.0].active = YES;
    [self.unreadBadge.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor].active = YES;
    [self.unreadBadge.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2.0].active = YES;
    [self.unreadBadge.bottomAnchor constraintLessThanOrEqualToAnchor:margins.bottomAnchor].active = YES;
    [self.unreadBadge setContentHuggingPriority:500 forAxis:UILayoutConstraintAxisHorizontal];
    [self.unreadBadge setContentCompressionResistancePriority:1000 forAxis:UILayoutConstraintAxisHorizontal];

    self.unreadLabel = [UILabel new];
    self.unreadLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.unreadLabel.textColor = [UIColor whiteColor];
    self.unreadLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.unreadLabel.textAlignment = NSTextAlignmentCenter;
    [self.unreadBadge addSubview:self.unreadLabel];
    self.unreadLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.unreadLabel autoVCenterInSuperview];
    [self.unreadLabel autoPinWidthToSuperview];
}

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
                                                                                         NSFontAttributeName : [UIFont ows_mediumFontWithSize:12],
                                                                                         NSForegroundColorAttributeName : [UIColor ows_blackColor],
                                                                                         }]];
    } else {
        if ([thread isMuted]) {
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:@"\ue067  "
                                                 attributes:@{
                                                              NSFontAttributeName : [UIFont ows_elegantIconsFont:9.f],
                                                              NSForegroundColorAttributeName : (thread.hasUnreadMessages
                                                                                                ? [UIColor colorWithWhite:0.1f alpha:1.f]
                                                                                                : [UIColor lightGrayColor]),
                                                              }]];
        }
        NSString *displayableText = [DisplayableText displayableText:thread.lastMessageLabel];
        if (displayableText) {
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                    initWithString:displayableText
                                                        attributes:@{
                                                            NSFontAttributeName : (thread.hasUnreadMessages
                                                                    ? [UIFont ows_mediumFontWithSize:12]
                                                                    : [UIFont ows_regularFontWithSize:12]),
                                                            NSForegroundColorAttributeName :
                                                                (thread.hasUnreadMessages ? [UIColor ows_blackColor]
                                                                                          : [UIColor lightGrayColor]),
                                                        }]];
        }
    }
    [snippetText appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];

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

    self.separatorInset = UIEdgeInsetsMake(0, self.contentView.layoutMargins.left, 0, 0);

    _timeLabel.textColor = thread.hasUnreadMessages ? [UIColor ows_materialBlueColor] : [UIColor ows_darkGrayColor];

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

    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:timeString];

    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:[UIColor ows_darkGrayColor]
                             range:NSMakeRange(0, timeString.length)];


    [attributedString addAttribute:NSFontAttributeName
                             value:[UIFont ows_regularFontWithSize:TIME_LABEL_SIZE]
                             range:NSMakeRange(0, timeString.length)];


    return attributedString;
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
                                                                          secondaryFont:[UIFont ows_footnoteFont]];
    }
    
    self.nameLabel.attributedText = name;
}

@end

NS_ASSUME_NONNULL_END
