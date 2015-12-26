//
//  TableViewCell.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "InboxTableViewCell.h"
#import "JSQMessagesAvatarImageFactory.h"
#import "PreferencesUtil.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSMessagesManager.h"
#import "UIImage+JSQMessages.h"
#import "Util.h"

#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 11
#define DATE_LABEL_SIZE 13
#define SWIPE_ARCHIVE_OFFSET -50

@interface InboxTableViewCell ()

@property NSUInteger unreadMessages;
@property UIView *messagesBadge;
@property UILabel *unreadLabel;

@end

@implementation InboxTableViewCell

+ (instancetype)inboxTableViewCell {
    InboxTableViewCell *cell =
        [NSBundle.mainBundle loadNibNamed:NSStringFromClass(self.class) owner:self options:nil][0];

    [cell initializeLayout];
    return cell;
}

- (void)initializeLayout {
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

- (void)configureWithThread:(TSThread *)thread {
    if (!_threadId || ![_threadId isEqualToString:thread.uniqueId]) {
        self.hidden = YES;
    }

    NSString *name                     = thread.name;
    _threadId                          = thread.uniqueId;
    NSString *snippetLabel             = thread.lastMessageLabel;
    NSAttributedString *attributedDate = [self dateAttributedString:thread.lastMessageDate];
    NSUInteger unreadCount             = [[TSMessagesManager sharedManager] unreadMessagesInThread:thread];

    dispatch_async(dispatch_get_main_queue(), ^{
      _nameLabel.text           = name;
      _snippetLabel.text        = snippetLabel;
      _timeLabel.attributedText = attributedDate;

      if ([thread isKindOfClass:[TSGroupThread class]]) {
          _contactPictureView.image = ((TSGroupThread *)thread).groupModel.groupImage != nil
                                          ? ((TSGroupThread *)thread).groupModel.groupImage
                                          : [UIImage imageNamed:@"empty-group-avatar"];
          if ([_nameLabel.text length] == 0) {
              _nameLabel.text = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
          }
          if (_contactPictureView.image != nil) {
              dispatch_async(dispatch_get_main_queue(), ^{
                [UIUtil applyRoundedBorderToImageView:&_contactPictureView];
              });
          }
      } else {
          NSMutableString *initials = [NSMutableString string];

          if ([name length] > 0) {
              NSArray *words = [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
              for (NSString *word in words) {
                  if ([word length] > 0) {
                      NSString *firstLetter = [word substringToIndex:1];
                      [initials appendString:[firstLetter uppercaseString]];
                  }
              }
          }

          NSRange stringRange = {0, MIN([initials length], (NSUInteger)3)}; // Rendering max 3 letters.
          initials            = [[initials substringWithRange:stringRange] mutableCopy];

          UIColor *backgroundColor =
              thread.isGroupThread ? [UIColor whiteColor]
                                   : [UIColor backgroundColorForContact:((TSContactThread *)thread).contactIdentifier];
          dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            UIImage *image =
                [[JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials
                                                            backgroundColor:backgroundColor
                                                                  textColor:[UIColor whiteColor]
                                                                       font:[UIFont ows_boldFontWithSize:36.0]
                                                                   diameter:100] avatarImage];
            dispatch_async(dispatch_get_main_queue(), ^{
              _contactPictureView.image = thread.image != nil ? thread.image : image;

              if (thread.image != nil) {
                  [UIUtil applyRoundedBorderToImageView:&_contactPictureView];
              }
            });
          });
      }

      self.separatorInset = UIEdgeInsetsMake(0, _contactPictureView.frame.size.width * 1.5f, 0, 0);

      if (thread.hasUnreadMessages) {
          [self updateCellForUnreadMessage];
      } else {
          [self updateCellForReadMessage];
      }
      [self setUnreadMsgCount:unreadCount];
      self.hidden = NO;
    });
}

- (void)updateCellForUnreadMessage {
    _nameLabel.font         = [UIFont ows_boldFontWithSize:14.0f];
    _nameLabel.textColor    = [UIColor ows_blackColor];
    _snippetLabel.font      = [UIFont ows_mediumFontWithSize:12];
    _snippetLabel.textColor = [UIColor ows_blackColor];
    _timeLabel.textColor    = [UIColor ows_materialBlueColor];
}

- (void)updateCellForReadMessage {
    _nameLabel.font         = [UIFont ows_boldFontWithSize:14.0f];
    _nameLabel.textColor    = [UIColor ows_blackColor];
    _snippetLabel.font      = [UIFont ows_regularFontWithSize:12];
    _snippetLabel.textColor = [UIColor lightGrayColor];
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
            _unreadLabel.frame =
                CGRectMake(offset.x + floor((2.0f * (25 - _unreadLabel.frame.size.width) / 2.0f) / 2.0f),
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
