#import "NotificationTracker.h"
#import "CryptoTools.h"
#import "NSData+CryptoTools.h"
#import "NSArray+FunctionalUtil.h"

#define MAX_NOTIFICATIONS_TO_TRACK 100
#define NOTIFICATION_PAYLOAD_KEY @"m"

@interface NotificationTracker ()

@property (strong, nonatomic) NSMutableArray* witnessedNotifications;

@end

@implementation NotificationTracker

- (instancetype)init {
    self = [super init];
	
    if (self) {
        self.witnessedNotifications = [[NSMutableArray alloc] init];
    }
    
    return self;
}

- (BOOL)shouldProcessNotification:(NSDictionary*)notification {
    BOOL should = ![self wasNotificationProcessed:notification];
    if (should) {
        [self markNotificationAsProcessed:notification];
    }
    return should;
}

- (void)markNotificationAsProcessed:(NSDictionary*)notification {
    NSData* data = [self getIdForNotification:notification];
    [self.witnessedNotifications insertObject:data atIndex:0];
    
    while (MAX_NOTIFICATIONS_TO_TRACK < self.witnessedNotifications.count) {
        [self.witnessedNotifications removeLastObject];
    }
}

- (BOOL)wasNotificationProcessed:(NSDictionary*)notification {
    NSData* data = [self getIdForNotification:notification];
    
    return [self.witnessedNotifications any:^int(NSData* previousData) {
        return [data isEqualToData:previousData];
    }];
}

// Uniquely Identify a notification by the hash of the message payload.
- (NSData*)getIdForNotification:(NSDictionary*)notification {
    NSData* data = [notification[NOTIFICATION_PAYLOAD_KEY] dataUsingEncoding:NSUTF8StringEncoding];
    NSData* notificationHash = [data hashWithSHA256];
    return notificationHash;
}

@end
