//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// We often use notifications as way to publish events.
//
// We never need these events to be received synchronously,
// so we should always send them asynchronously to avoid any
// possible risk of deadlock.  These methods also ensure that
// the notifications are always fired on the main thread.
@interface NSNotificationCenter (OWS)

- (void)postNotificationNameAsync:(NSNotificationName)name object:(nullable id)object;
- (void)postNotificationNameAsync:(NSNotificationName)name
                           object:(nullable id)object
                         userInfo:(nullable NSDictionary *)userInfo;

@end

NS_ASSUME_NONNULL_END
