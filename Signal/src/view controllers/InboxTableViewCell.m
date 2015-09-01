//
//  TableViewCell.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "InboxTableViewCell.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "Util.h"
#import "UIImage+JSQMessages.h"
#import "TSGroupThread.h"
#import "TSContactThread.h"
#import "JSQMessagesAvatarImageFactory.h"
#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 11
#define DATE_LABEL_SIZE 13
#define SWIPE_ARCHIVE_OFFSET -50

@implementation InboxTableViewCell

+ (instancetype)inboxTableViewCell {
    InboxTableViewCell *cell = [NSBundle.mainBundle loadNibNamed:NSStringFromClass(self.class)
                                                           owner:self
                                                         options:nil][0];
    
    [cell initializeLayout];
    return cell;
}

- (void)initializeLayout {
    _scrollView.contentSize   = CGSizeMake(CGRectGetWidth(_contentContainerView.bounds),
                                           CGRectGetHeight(_scrollView.frame));
    
    _scrollView.contentOffset = CGPointMake(CGRectGetWidth(_archiveView.frame), 0);
    _archiveImageView.image   = [_archiveImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

-(void)configureWithThread:(TSThread*)thread {
    _nameLabel.text           = thread.name;
    _snippetLabel.text        = thread.lastMessageLabel;
    _timeLabel.attributedText = [self dateAttributedString:thread.lastMessageDate];
    if([thread isKindOfClass:[TSGroupThread class]]) {
        _contactPictureView.image = ((TSGroupThread*)thread).groupModel.groupImage!=nil ? ((TSGroupThread*)thread).groupModel.groupImage : [UIImage imageNamed:@"empty-group-avatar"];
        if([_nameLabel.text length]==0) {
            _nameLabel.text = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
        }
        if(_contactPictureView.image!=nil) {
            [UIUtil applyRoundedBorderToImageView:&_contactPictureView];
        }
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
        
        NSRange stringRange = {0, MIN([initials length], (NSUInteger)3)}; //Rendering max 3 letters.
        initials = [[initials substringWithRange:stringRange] mutableCopy];
        
        UIColor *backgroundColor = thread.isGroupThread ? [UIColor whiteColor] : [UIColor backgroundColorForContact:((TSContactThread*)thread).contactIdentifier];
        UIImage* image = [[JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials backgroundColor:backgroundColor textColor:[UIColor whiteColor] font:[UIFont ows_boldFontWithSize:36.0] diameter:100] avatarImage];
        _contactPictureView.image = thread.image!=nil ? thread.image : image;
        if(thread.image!=nil) {
            [UIUtil applyRoundedBorderToImageView:&_contactPictureView];
        }
    }
    
    self.separatorInset = UIEdgeInsetsMake(0,_contactPictureView.frame.size.width*1.5f, 0, 0);
    
    if (thread.hasUnreadMessages) {
        [self updateCellForUnreadMessage];
    }
}

-(void)configureForState:(CellState)state
{
    switch (state) {
        case kArchiveState:
            _archiveImageView.image = [[UIImage imageNamed:@"cellBtnMoveToInbox--blue"]imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            break;
        case kInboxState:
            break;
            
        default:
            break;
    }
}

-(void)updateCellForUnreadMessage
{
    _nameLabel.font         = [UIFont ows_boldFontWithSize:14.0f];
    _snippetLabel.textColor = [UIColor ows_blackColor];
    _timeLabel.textColor    = [UIColor ows_materialBlueColor];
}

-(void)updateCellForReadMessage
{
    _nameLabel.font         = [UIFont ows_regularFontWithSize:14.0f];
    _snippetLabel.textColor = [UIColor lightGrayColor];
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
        [Environment.preferences setHasArchivedAMessage:YES];
    }
    else {
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
