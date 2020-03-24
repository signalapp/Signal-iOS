//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const AppDelegateStoryboardMain;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

- (void)startPollerIfNeeded;
- (void)stopPollerIfNeeded;
- (void)setUpDefaultPublicChatsIfNeeded;
- (void)startOpenGroupPollersIfNeeded;
- (void)stopOpenGroupPollersIfNeeded;
- (void)createRSSFeedsIfNeeded;
- (void)startRSSFeedPollersIfNeeded;

@end
