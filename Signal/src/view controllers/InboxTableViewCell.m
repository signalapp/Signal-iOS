//
//  TableViewCell.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "InboxTableViewCell.h"
#import "Util.h"
#import "UIImage+JSQMessages.h"
#import "TSGroupThread.h"
#import "JSQMessagesAvatarImageFactory.h"
#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 11
#define DATE_LABEL_SIZE 13
#define SWIPE_ARCHIVE_OFFSET -50

@implementation InboxTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [NSBundle.mainBundle loadNibNamed:NSStringFromClass(self.class)
                                       owner:self
                                     options:nil][0];
    
    
    if (self) {
        _scrollView.contentSize   = CGSizeMake(CGRectGetWidth(_contentContainerView.bounds),
                                             CGRectGetHeight(_scrollView.frame));

        [UIUtil applyRoundedBorderToImageView:&_contactPictureView];
        
        _scrollView.contentOffset = CGPointMake(CGRectGetWidth(_archiveView.frame), 0);
        _deleteImageView.image    = [_deleteImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        _archiveImageView.image   = [_archiveImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        _lastActionImageView.image = [_lastActionImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        
    }
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

-(void)configureWithThread:(TSThread*)thread {
    _nameLabel.text           = thread.name;
    _snippetLabel.text        = thread.lastMessageLabel;
    _timeLabel.attributedText = [self dateAttributedString:thread.lastMessageDate];
    if([thread isKindOfClass:[TSGroupThread class]] ) {
        _contactPictureView.image = ((TSGroupThread*)thread).groupModel.groupImage!=nil ? ((TSGroupThread*)thread).groupModel.groupImage : [UIImage imageNamed:@"empty-group-avatar@1x"];
    }
    else {
        NSMutableString *initials = [NSMutableString string];
        if([thread.name length]>0) {
            NSArray *words = [thread.name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            for (NSString * word in words) {
                if ([word length] > 0) {
                    NSString *firstLetter = [word substringToIndex:1];
                    [initials appendString:[firstLetter uppercaseString]];
                }
            }
        }
        UIImage* image = [[JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials backgroundColor:[UIColor whiteColor] textColor:[UIColor ows_materialBlueColor] font:[UIFont ows_regularFontWithSize:36.0] diameter:100] avatarImage];
        _contactPictureView.image = thread.image!=nil ? thread.image : image;
    }

    self.separatorInset       = UIEdgeInsetsMake(0,_contactPictureView.frame.size.width*1.5f, 0, 0);

    [self setUpLastActionForThread:thread];
}

-(void)configureForState:(CellState)state
{
    switch (state) {
        case kArchiveState:
            _archiveImageView.image = [[UIImage imageNamed:@"reply"]imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            break;
        case kInboxState:
            break;
            
        default:
            break;
    }
}

-(void)setUpLastActionForThread:(TSThread*)thread
{
    TSLastActionType lastAction = [thread lastAction];
    
    switch (lastAction) {
        case TSLastActionNone:
            _lastActionImageView.image = nil;
            break;
        case TSLastActionCallIncoming:
            _lastActionImageView.image = [UIImage imageNamed:@"call_incoming"];
            break;
        case TSLastActionCallIncomingMissed:
            _lastActionImageView.image = [UIImage imageNamed:@"call_missed"];
            break;
        case TSLastActionCallOutgoing:
            _lastActionImageView.image = [UIImage imageNamed:@"call_outgoing"];
            break;
        case TSLastActionCallOutgoingMissed:
            _lastActionImageView.image = [UIImage imageNamed:@"call_canceled"];
            break;
        case TSLastActionCallOutgoingFailed:
            _lastActionImageView.image = [UIImage imageNamed:@"call_failed"];
            break;
        case TSLastActionMessageAttemptingOut:
            _lastActionImageView.image = nil;
            break;
        case TSLastActionMessageUnsent:
            _lastActionImageView.image = [UIImage imageNamed:@"message_error"];
            break;
        case TSLastActionMessageSent:
            _lastActionImageView.image = [UIImage imageNamed:@"reply"];
            break;
        case TSLastActionMessageDelivered:
            _lastActionImageView.image = [UIImage imageNamed:@"checkmark_light"];
            break;
        case TSLastActionMessageIncomingRead:
            _lastActionImageView.image = nil;
            break;
        case TSLastActionMessageIncomingUnread:
            [self updateCellForUnreadMessage];
            _lastActionImageView.image = nil;
            break;
        case TSLastActionInfoMessage:
            _lastActionImageView.image = [UIImage imageNamed:@"warning_white"];
            break;
        case TSLastActionErrorMessage:
            _lastActionImageView.image = [UIImage imageNamed:@"error_white"];
            break;
        default:
            _lastActionImageView.image = nil;
            break;
    }
}

-(void)updateCellForUnreadMessage
{
    _nameLabel.font = [UIFont ows_boldFontWithSize:14.0f];
    _snippetLabel.textColor = [UIColor ows_blackColor];
    _timeLabel.textColor = [UIColor ows_materialBlueColor];
}

-(void)updateCellForReadMessage
{
    _nameLabel.font = [UIFont ows_regularFontWithSize:14.0f];
    _snippetLabel.textColor = [UIColor lightGrayColor];
}

#pragma mark - Date formatting

- (NSAttributedString *)dateAttributedString:(NSDate *)date {
    
    NSString *timeString = [[DateUtil timeFormatter] stringFromDate:date];
    
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:timeString];
    
    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:[UIColor ows_darkGrayColor]
                             range:NSMakeRange(0, timeString.length)];
    

    
    [attributedString addAttribute:NSFontAttributeName
                             value:[UIFont ows_regularFontWithSize:TIME_LABEL_SIZE]
                             range:NSMakeRange(0, timeString.length)];

    
    return attributedString;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    if (_scrollView.contentOffset.x < 0) {
        _archiveImageView.image = [_archiveImageView.image jsq_imageMaskedWithColor:[UIColor ows_materialBlueColor]];
        _archiveImageView.bounds = CGRectMake(_archiveImageView.bounds.origin.x,
                                              _archiveImageView.bounds.origin.y,
                                              ARCHIVE_IMAGE_VIEW_WIDTH,
                                              _archiveImageView.bounds.size.height);
    } else {
        
        _archiveImageView.image = [_archiveImageView.image jsq_imageMaskedWithColor:[UIColor ows_darkGrayColor]];
        double ratio = (_archiveView.frame.size.width/2.0f - _scrollView.contentOffset.x) / (_archiveView.frame.size.width/2.0f);
        double newWidth = ARCHIVE_IMAGE_VIEW_WIDTH/2.0f + (ARCHIVE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        _archiveImageView.bounds = CGRectMake(_archiveImageView.bounds.origin.x,
                                              _archiveImageView.bounds.origin.y,
                                              (CGFloat)newWidth,
                                              _archiveImageView.bounds.size.height);
        
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    
    if (_scrollView.contentOffset.x < SWIPE_ARCHIVE_OFFSET) {
        // archive the thread
        [_delegate tableViewCellTappedArchive:self];
    } else {
        // don't do anything
        *targetContentOffset = CGPointMake(CGRectGetWidth(_archiveView.frame), 0);
    }
}

#pragma mark - Animation

-(void)animateDisappear
{
    [UIView animateWithDuration:1.0f animations:^(){
        self.alpha = 0;
    }];
}


@end
