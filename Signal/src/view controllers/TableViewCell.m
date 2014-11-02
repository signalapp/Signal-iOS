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
        _deleteImageView.image    = [_deleteImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _archiveImageView.image   = [_archiveImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
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
    
}

#pragma mark - Date formatting

- (NSAttributedString *)dateArrributedString:(NSDate *)date {
    
    NSString *dateString;
    NSString *timeString = [[DateUtil timeFormatter] stringFromDate:date];
    
    
    if ([DateUtil dateIsOlderThanOneWeek:date]) {
        dateString = [[DateUtil dateFormatter] stringFromDate:date];
    } else {
        dateString = [[DateUtil weekdayFormatter] stringFromDate:date];
    }
    
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:[timeString stringByAppendingString:dateString]];
    
    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:[UIColor darkGrayColor]
                             range:NSMakeRange(0, timeString.length)];
    
    [attributedString addAttribute:NSForegroundColorAttributeName
                             value:[UIUtil darkBackgroundColor]
                             range:NSMakeRange(timeString.length,dateString.length)];
    
    [attributedString addAttribute:NSFontAttributeName
                             value:[UIUtil helveticaLightWithSize:TIME_LABEL_SIZE]
                             range:NSMakeRange(0, timeString.length)];
    
    [attributedString addAttribute:NSFontAttributeName
                             value:[UIUtil helveticaRegularWithSize:DATE_LABEL_SIZE]
                             range:NSMakeRange(timeString.length,dateString.length)];
    
    return attributedString;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    if (_scrollView.contentOffset.x < 0) {
        _archiveImageView.tintColor = [UIUtil redColor];
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
        _deleteImageView.tintColor = [UIUtil redColor];
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




@end
