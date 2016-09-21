//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import <UIKit/UIKit.h>
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;

typedef enum : NSUInteger { kArchiveState = 0, kInboxState = 1 } CellState;

@interface InboxTableViewCell : UITableViewCell <UIScrollViewDelegate>

@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UILabel *snippetLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactPictureView;
@property (nonatomic, strong) IBOutlet UILabel *timeLabel;
@property (nonatomic, strong) IBOutlet UIView *contentContainerView;
@property (nonatomic, retain) IBOutlet UIView *messageCounter;
@property (nonatomic, retain) NSString *threadId;

+ (instancetype)inboxTableViewCell;

- (void)configureWithThread:(TSThread *)thread contactsManager:(OWSContactsManager *)contactsManager;
- (void)animateDisappear;

@end

NS_ASSUME_NONNULL_END
