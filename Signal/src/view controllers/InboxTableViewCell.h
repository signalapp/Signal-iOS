//
//  TableViewCell.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NextResponderScrollView.h"
#import "TSThread.h"

typedef enum : NSUInteger {
    kArchiveState = 0,
    kInboxState = 1
} CellState;


@class InboxTableViewCell;
@protocol TableViewCellDelegate <NSObject>

- (void)tableViewCellTappedArchive:(InboxTableViewCell *)cell;

@end

@interface InboxTableViewCell : UITableViewCell  <UIScrollViewDelegate>

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UILabel * snippetLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactPictureView;
@property (nonatomic, strong) IBOutlet UILabel *timeLabel;
@property (nonatomic, strong) IBOutlet NextResponderScrollView *scrollView;
@property (nonatomic, strong) IBOutlet UIView *contentContainerView;

@property (nonatomic, strong) IBOutlet UIView *archiveView;
@property (nonatomic, strong) IBOutlet UIImageView *archiveImageView;
@property (nonatomic, assign) id<TableViewCellDelegate> delegate;

+ (instancetype)inboxTableViewCell;
- (void)configureWithThread:(TSThread*)thread;
- (void)configureForState:(CellState)state;
- (void)animateDisappear;

@end
