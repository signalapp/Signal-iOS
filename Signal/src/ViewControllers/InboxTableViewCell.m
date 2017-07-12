//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "InboxTableViewCell.h"
#import "OWSAvatarBuilder.h"
#import "Signal-Swift.h"
#import "Util.h"
#import "ViewControllerUtils.h"
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSMessagesManager.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 11
#define DATE_LABEL_SIZE 13
#define SWIPE_ARCHIVE_OFFSET -50

const NSUInteger kavatarViewDiameter = 52;

@interface InboxTableViewCell ()

@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *snippetLabel;
@property (nonatomic) UILabel *timeLabel;
@property (nonatomic) UIView *unreadBadge;
@property (nonatomic) UILabel *unreadLabel;

@property (nonatomic) NSString *threadId;

@end

#pragma mark -

@implementation InboxTableViewCell

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
    self.preservesSuperviewLayoutMargins = YES;
    self.contentView.preservesSuperviewLayoutMargins = YES;

    self.backgroundColor = [UIColor whiteColor];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:52.f];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:52.f];
    [self.avatarView autoPinLeadingToSuperView];
    [self.avatarView autoVCenterInSuperview];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.nameLabel];
    [self.nameLabel autoPinLeadingToTrailingOfView:self.avatarView margin:13.f];
    [self.nameLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.avatarView];
    [self.nameLabel setContentHuggingHorizontalLow];

    self.snippetLabel = [UILabel new];
    self.snippetLabel.font = [UIFont ows_regularFontWithSize:14.f];
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.snippetLabel.textColor = [UIColor colorWithWhite:2 / 3.f alpha:1.f];
    self.snippetLabel.numberOfLines = 2;
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:self.snippetLabel];
    [self.snippetLabel autoPinLeadingToTrailingOfView:self.avatarView margin:13.f];
    [self.snippetLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.nameLabel withOffset:5.f];
    [self.snippetLabel autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:self.nameLabel];
    [self.snippetLabel setContentHuggingHorizontalLow];

    self.timeLabel = [UILabel new];
    self.timeLabel.font = [UIFont ows_lightFontWithSize:14.f];
    [self.contentView addSubview:self.timeLabel];
    [self.timeLabel autoPinTrailingToSuperView];
    [self.timeLabel autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.nameLabel];
    [self.timeLabel autoPinLeadingToTrailingOfView:self.nameLabel margin:10.f];
    [self.timeLabel setContentHuggingHorizontalHigh];
    [self.timeLabel setCompressionResistanceHigh];

    const int kunreadBadgeSize = 24;
    self.unreadBadge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kunreadBadgeSize, kunreadBadgeSize)];
    self.unreadBadge.layer.cornerRadius = kunreadBadgeSize / 2;
    self.unreadBadge.backgroundColor = [UIColor ows_materialBlueColor];
    [self.contentView addSubview:self.unreadBadge];
    [self.unreadBadge autoSetDimension:ALDimensionWidth toSize:kunreadBadgeSize];
    [self.unreadBadge autoSetDimension:ALDimensionHeight toSize:kunreadBadgeSize];
    [self.unreadBadge autoPinTrailingToSuperView];
    [self.unreadBadge autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.avatarView];
    [self.unreadBadge setContentHuggingHorizontalHigh];
    [self.unreadBadge setCompressionResistanceHigh];

    self.unreadLabel = [UILabel new];
    self.unreadLabel.font = [UIFont ows_regularFontWithSize:12.f];
    self.unreadLabel.textColor = [UIColor whiteColor];
    self.unreadLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.unreadLabel.textAlignment = NSTextAlignmentCenter;
    [self.unreadBadge addSubview:self.unreadLabel];
    [self.unreadLabel autoVCenterInSuperview];
    [self.unreadLabel autoPinWidthToSuperview];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

+ (CGFloat)rowHeight
{
    return 72.f;
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

    BOOL isBlocked = NO;
    if (!thread.isGroupThread) {
        NSString *contactIdentifier = thread.contactIdentifier;
        isBlocked = [blockedPhoneNumberSet containsObject:contactIdentifier];
    }

    NSString *name = thread.name;
    if (name.length == 0 && [thread isKindOfClass:[TSGroupThread class]]) {
        name = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }
    self.threadId = thread.uniqueId;
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
        NSString *displayableText = [[DisplayableTextFilter new] displayableText:thread.lastMessageLabel];
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

    NSAttributedString *attributedDate = [self dateAttributedString:thread.lastMessageDate];
    NSUInteger unreadCount = [[TSMessagesManager sharedManager] unreadMessagesInThread:thread];

    self.nameLabel.text = name;
    self.snippetLabel.attributedText = snippetText;
    self.timeLabel.attributedText = attributedDate;
    self.avatarView.image = nil;

    self.separatorInset = UIEdgeInsetsMake(0, _avatarView.frame.size.width * 1.5f, 0, 0);

    if (thread.hasUnreadMessages) {
        [self updateCellForUnreadMessage];
    } else {
        [self updateCellForReadMessage];
    }
    if (unreadCount > 0) {
        self.unreadBadge.hidden = NO;
        self.unreadLabel.hidden = NO;
        self.unreadLabel.text = [ViewControllerUtils formatInt:MIN(99, (int)unreadCount)];
    } else {
        self.unreadBadge.hidden = YES;
        self.unreadLabel.hidden = YES;
    }

    NSString *threadIdCopy = thread.uniqueId;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *avatar =
            [OWSAvatarBuilder buildImageForThread:thread contactsManager:contactsManager diameter:kavatarViewDiameter];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([_threadId isEqualToString:threadIdCopy]) {
                self.avatarView.image = avatar;
            }
        });
    });
}

- (void)updateCellForUnreadMessage {
    _nameLabel.font         = [UIFont ows_boldFontWithSize:14.0f];
    _nameLabel.textColor    = [UIColor ows_blackColor];
    _timeLabel.textColor    = [UIColor ows_materialBlueColor];
}

- (void)updateCellForReadMessage {
    _nameLabel.font         = [UIFont ows_boldFontWithSize:14.0f];
    _nameLabel.textColor    = [UIColor ows_blackColor];
    _timeLabel.textColor    = [UIColor ows_darkGrayColor];
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
}

@end

NS_ASSUME_NONNULL_END
