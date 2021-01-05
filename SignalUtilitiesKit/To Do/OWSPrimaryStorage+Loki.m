#import "OWSPrimaryStorage+Loki.h"
#import "OWSPrimaryStorage+keyFromIntLong.h"
#import "OWSIdentityManager.h"
#import "NSDate+OWS.h"
#import "TSAccountManager.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import "NSObject+Casting.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

@implementation OWSPrimaryStorage (Loki)

# pragma mark - Convenience

- (OWSIdentityManager *)identityManager {
    return OWSIdentityManager.sharedManager;
}

- (TSAccountManager *)accountManager {
    return TSAccountManager.sharedInstance;
}

# pragma mark - Open Groups

#define LKMessageIDCollection @"LKMessageIDCollection"

- (void)setIDForMessageWithServerID:(NSUInteger)serverID to:(NSString *)messageID in:(YapDatabaseReadWriteTransaction *)transaction {
    NSString *key = [NSString stringWithFormat:@"%@", @(serverID)];
    [transaction setObject:messageID forKey:key inCollection:LKMessageIDCollection];
}

- (NSString *_Nullable)getIDForMessageWithServerID:(NSUInteger)serverID in:(YapDatabaseReadTransaction *)transaction {
    NSString *key = [NSString stringWithFormat:@"%@", @(serverID)];
    return [transaction objectForKey:key inCollection:LKMessageIDCollection];
}

- (void)updateMessageIDCollectionByPruningMessagesWithIDs:(NSSet<NSString *> *)targetMessageIDs in:(YapDatabaseReadWriteTransaction *)transaction {
    NSMutableArray<NSString *> *serverIDs = [NSMutableArray new];
    [transaction enumerateRowsInCollection:LKMessageIDCollection usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
        if (![object isKindOfClass:NSString.class]) { return; }
        NSString *messageID = (NSString *)object;
        if (![targetMessageIDs containsObject:messageID]) { return; }
        [serverIDs addObject:key];
    }];
    [transaction removeObjectsForKeys:serverIDs inCollection:LKMessageIDCollection];
}

# pragma mark - Restoration from Seed

#define LKGeneralCollection @"Loki"

- (void)setRestorationTime:(NSTimeInterval)time {
    [self.dbReadWriteConnection setDouble:time forKey:@"restoration_time" inCollection:LKGeneralCollection];
}

- (NSTimeInterval)getRestorationTime {
    return [self.dbReadConnection doubleForKey:@"restoration_time" inCollection:LKGeneralCollection defaultValue:0];
}

@end
