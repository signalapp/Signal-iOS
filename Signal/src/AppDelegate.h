//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const AppDelegateStoryboardMain;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

- (void)startLongPollerIfNeeded;
- (void)stopLongPollerIfNeeded;
- (void)createGroupChatsIfNeeded;
- (void)createRSSFeedsIfNeeded;
- (void)startGroupChatPollersIfNeeded;
- (void)startRSSFeedPollersIfNeeded;

@end
