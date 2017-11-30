//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^BackgroundTaskExpirationHandler)(void);

@protocol AppContext <NSObject>

- (BOOL)isMainApp;
- (BOOL)isMainAppAndActive;

- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithExpirationHandler:
    (BackgroundTaskExpirationHandler)expirationHandler;

@end

id<AppContext> CurrentAppContext();
void SetCurrentAppContext(id<AppContext> appContext);

NS_ASSUME_NONNULL_END
