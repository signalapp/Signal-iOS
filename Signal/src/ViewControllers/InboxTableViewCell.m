//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "InboxTableViewCell.h"
#import "Environment.h"
#import "OWSAvatarBuilder.h"
#import "OWSContactAvatarBuilder.h"
#import "PropertyListPreferences.h"
#import "Signal-Swift.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSMessagesManager.h"
#import "Util.h"
#import <JSQMessagesViewController/JSQMessagesAvatarImageFactory.h>
#import <JSQMessagesViewController/UIImage+JSQMessages.h>
#import <SignalServiceKit/OWSBlockingManager.h>

NS_ASSUME_NONNULL_BEGIN

#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 11
#define DATE_LABEL_SIZE 13
#define SWIPE_ARCHIVE_OFFSET -50

@interface InboxTableViewCell ()

@property (nonatomic) NSUInteger unreadMessages;
@property (nonatomic) UIView *messagesBadge;
@property (nonatomic) UILabel *unreadLabel;

@end

#pragma mark -

@implementation InboxTableViewCell

+ (instancetype)inboxTableViewCell {
    InboxTableViewCell *cell =
        [NSBundle.mainBundle loadNibNamed:NSStringFromClass(self.class) owner:self options:nil][0];

    [cell initializeLayout];
    return cell;
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
    self.contactPictureView.image = nil;

    self.separatorInset = UIEdgeInsetsMake(0, _contactPictureView.frame.size.width * 1.5f, 0, 0);

    if (thread.hasUnreadMessages) {
        [self updateCellForUnreadMessage];
    } else {
        [self updateCellForReadMessage];
    }
    [self setUnreadMsgCount:unreadCount];

    NSString *threadIdCopy = thread.uniqueId;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *avatar = [OWSAvatarBuilder buildImageForThread:thread contactsManager:contactsManager];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([_threadId isEqualToString:threadIdCopy]) {
                self.contactPictureView.image = avatar;
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

- (void)setUnreadMsgCount:(NSUInteger)unreadMessages {
    if (_unreadMessages != unreadMessages) {
        _unreadMessages = unreadMessages;

        if (_unreadMessages > 0) {
            if (_messagesBadge == nil) {
                static UIImage *backgroundImage = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                  UIGraphicsBeginImageContextWithOptions(CGSizeMake(25.0f, 25.0f), false, 0.0f);
                  CGContextRef context = UIGraphicsGetCurrentContext();
                  CGContextSetFillColorWithColor(context, [UIColor ows_materialBlueColor].CGColor);
                  CGContextFillEllipseInRect(context, CGRectMake(0.0f, 0.0f, 25.0f, 25.0f));
                  backgroundImage =
                      [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:8 topCapHeight:8];
                  UIGraphicsEndImageContext();
                });

                _messagesBadge = [[UIImageView alloc]
                    initWithFrame:CGRectMake(
                                      0.0f, 0.0f, _messageCounter.frame.size.height, _messageCounter.frame.size.width)];
                _messagesBadge.userInteractionEnabled = NO;
                _messagesBadge.layer.zPosition        = 2000;

                UIImageView *unreadBackground = [[UIImageView alloc] initWithImage:backgroundImage];
                [_messageCounter addSubview:unreadBackground];

                _unreadLabel                 = [[UILabel alloc] init];
                _unreadLabel.backgroundColor = [UIColor clearColor];
                _unreadLabel.textColor       = [UIColor whiteColor];
                _unreadLabel.font            = [UIFont systemFontOfSize:12];
                [_messageCounter addSubview:_unreadLabel];
            }

            _unreadLabel.text = [[NSNumber numberWithUnsignedInteger:unreadMessages] stringValue];
            [_unreadLabel sizeToFit];

            CGPoint offset = CGPointMake(0.0f, 5.0f);
            _unreadLabel.frame
                = CGRectMake(offset.x + (CGFloat)floor((2.0f * (25.0f - _unreadLabel.frame.size.width) / 2.0f) / 2.0f),
                    offset.y,
                    _unreadLabel.frame.size.width,
                    _unreadLabel.frame.size.height);
            _messageCounter.hidden = NO;
        } else {
            _messageCounter.hidden = YES;
        }
    }
}

#pragma mark - Animation

- (void)animateDisappear {
    [UIView animateWithDuration:1.0f
                     animations:^() {
                       self.alpha = 0;
                     }];
}


@end

NS_ASSUME_NONNULL_END
