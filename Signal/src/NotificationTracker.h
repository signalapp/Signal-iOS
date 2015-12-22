#import <Foundation/Foundation.h>

/**
 *  Tracks which notifications have already been processed, and which are are seen for the first time.
 **/

@interface NotificationTracker : NSObject

+ (NotificationTracker *)notificationTracker;
- (BOOL)shouldProcessNotification:(NSDictionary *)notification;

@end
