#import "CryptoTools.h"
#import "FunctionalUtil.h"
#import "NotificationTracker.h"

#define MAX_NOTIFICATIONS_TO_TRACK 100
#define NOTIFICATION_PAYLOAD_KEY @"m"

@implementation NotificationTracker {
    NSMutableArray *_witnessedNotifications;
}

+ (NotificationTracker *)notificationTracker {
    NotificationTracker *notificationTracker     = [NotificationTracker new];
    notificationTracker->_witnessedNotifications = [NSMutableArray new];
    return notificationTracker;
}

- (BOOL)shouldProcessNotification:(NSDictionary *)notification {
    BOOL should = ![self wasNotificationProcessed:notification];
    if (should) {
        [self markNotificationAsProcessed:notification];
    }
    return should;
}

- (void)markNotificationAsProcessed:(NSDictionary *)notification {
    NSData *data = [self getIdForNotification:notification];
    [_witnessedNotifications insertObject:data atIndex:0];

    while (MAX_NOTIFICATIONS_TO_TRACK < _witnessedNotifications.count) {
        [_witnessedNotifications removeLastObject];
    }
}

- (BOOL)wasNotificationProcessed:(NSDictionary *)notification {
    NSData *data = [self getIdForNotification:notification];

    return [_witnessedNotifications any:^int(NSData *previousData) {
      return [data isEqualToData:previousData];
    }];
}

// Uniquely Identify a notification by the hash of the message payload.
- (NSData *)getIdForNotification:(NSDictionary *)notification {
    NSData *data             = [notification[NOTIFICATION_PAYLOAD_KEY] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *notificationHash = [data hashWithSha256];
    return notificationHash;
}

@end
