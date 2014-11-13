//
//  TableViewCell.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TableViewCell.h"
#import "Util.h"

#define ARCHIVE_IMAGE_VIEW_WIDTH 22.0f
#define DELETE_IMAGE_VIEW_WIDTH 19.0f
#define TIME_LABEL_SIZE 10
#define DATE_LABEL_SIZE 13


@implementation TableViewCell

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
    }
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

-(void)configureWithTestMessage:(DemoDataModel*)testMessage {
    _nameLabel.text           = testMessage._sender;
    _snippetLabel.text        = testMessage._snippet;
    _contactPictureView.image = nil;
    _timeLabel.attributedText = [self dateArrributedString:[NSDate date]];
    self.separatorInset = UIEdgeInsetsMake(0,_contactPictureView.frame.size.width*1.5, 0, 0);

    [self setUpLastAction:testMessage.lastActionString];
    
}

-(void)configureForState:(CellState)state
{
    switch (state) {
        case kArchiveState:
            _scrollView.userInteractionEnabled=NO;
            break;
        case kInboxState:
            _scrollView.userInteractionEnabled=YES;
            break;
            
        default:
            break;
    }
}

-(void)setUpLastAction:(NSString*)lastAction {
    if ([lastAction isEqualToString:@"read"]) {
        _lastActionImageView.image = [UIImage imageNamed:@"checkmark"];
    } else if ([lastAction isEqualToString:@"replied"]) {
        _lastActionImageView.image = [UIImage imageNamed:@"reply"];
    } else if ([lastAction isEqualToString:@"missedCall"]) {
        _lastActionImageView.image = [UIImage imageNamed:@"missed"];
    } else if ([lastAction isEqualToString:@"outgoingCall"]) {
        _lastActionImageView.image = [UIImage imageNamed:@"received"];
    } else if ([lastAction isEqualToString:@"unread"]) {
        _lastActionImageView.image = nil;
        _snippetLabel.textColor = [UIColor blackColor];
        _nameLabel.font = [UIFont boldSystemFontOfSize:15];
        _timeLabel.textColor = [UIColor colorWithRed:0 green:91/255.f blue:1.0f alpha:1.0f];
    }

}

#pragma mark - Date formatting

- (NSAttributedString *)dateArrributedString:(NSDate *)date {
    
    NSString *timeString = [[DateUtil timeFormatter] stringFromDate:date];
    
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:timeString];
    
    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:[UIColor darkGrayColor]
                             range:NSMakeRange(0, timeString.length)];
    

    
    [attributedString addAttribute:NSFontAttributeName
                             value:[UIUtil helveticaLightWithSize:TIME_LABEL_SIZE]
                             range:NSMakeRange(0, timeString.length)];

    
    return attributedString;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    if (_scrollView.contentOffset.x < 0) {
        _archiveImageView.image = [UIImage imageNamed:@"blue-archive"];
        _archiveImageView.bounds = CGRectMake(_archiveImageView.bounds.origin.x,
                                              _archiveImageView.bounds.origin.y,
                                              ARCHIVE_IMAGE_VIEW_WIDTH,
                                              _archiveImageView.bounds.size.height);
    } else {
        
        double ratio = (_archiveView.frame.size.width/2.0f - _scrollView.contentOffset.x) / (_archiveView.frame.size.width/2.0f);
        double newWidth = ARCHIVE_IMAGE_VIEW_WIDTH/2 + (ARCHIVE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        _archiveImageView.bounds = CGRectMake(_archiveImageView.bounds.origin.x,
                                              _archiveImageView.bounds.origin.y,
                                              (CGFloat)newWidth,
                                              _archiveImageView.bounds.size.height);
        _archiveImageView.tintColor = UIColor.whiteColor;
        
    }
    
    if (scrollView.contentOffset.x > CGRectGetWidth(_archiveView.frame)*2) {
        _deleteImageView.image = [UIImage imageNamed:@"red-delete"];
        _deleteImageView.bounds = CGRectMake(_deleteImageView.bounds.origin.x,
                                             _deleteImageView.bounds.origin.y,
                                             DELETE_IMAGE_VIEW_WIDTH,
                                             _deleteImageView.bounds.size.height);
    } else {
        
        double ratio = _scrollView.contentOffset.x / (CGRectGetWidth(_deleteView.frame)*2);
        double newWidth = DELETE_IMAGE_VIEW_WIDTH/2 + (DELETE_IMAGE_VIEW_WIDTH * ratio)/2.0f;
        
        _deleteImageView.bounds = CGRectMake(_deleteImageView.bounds.origin.x,
                                             _deleteImageView.bounds.origin.y,
                                             (CGFloat)newWidth,
                                             _deleteImageView.bounds.size.height);
        _deleteImageView.tintColor = UIColor.whiteColor;
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    
    if (_scrollView.contentOffset.x < 0) {
        [_delegate tableViewCellTappedArchive:self];
    } else {
        *targetContentOffset = CGPointMake(CGRectGetWidth(_archiveView.frame), 0);
    }
    
    if (scrollView.contentOffset.x > CGRectGetWidth(_archiveView.frame)*2) {
        [_delegate tableViewCellTappedDelete:self];
    } else {
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
