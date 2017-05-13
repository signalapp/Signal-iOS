//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@class Contact;
@class OWSContactsManager;
@class AvatarImageView;

typedef enum : NSUInteger { kArchiveState = 0, kInboxState = 1 } CellState;

@interface InboxTableViewCell : UITableViewCell <UIScrollViewDelegate>

@property (nonatomic) IBOutlet UILabel *nameLabel;
@property (nonatomic) IBOutlet UILabel *snippetLabel;
@property (nonatomic) IBOutlet AvatarImageView *contactPictureView;
@property (nonatomic) IBOutlet UILabel *timeLabel;
@property (nonatomic) IBOutlet UIView *contentContainerView;
@property (nonatomic) IBOutlet UIView *messageCounter;
@property (nonatomic) NSString *threadId;
@property (nonatomic) NSString *contactId;

+ (instancetype)inboxTableViewCell;

+ (CGFloat)rowHeight;

- (void)configureWithThread:(TSThread *)thread
            contactsManager:(OWSContactsManager *)contactsManager
      blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet;

- (void)animateDisappear;

@end

NS_ASSUME_NONNULL_END
