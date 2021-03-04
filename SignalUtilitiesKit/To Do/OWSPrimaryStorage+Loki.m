#import "OWSPrimaryStorage+Loki.h"
#import "OWSPrimaryStorage+keyFromIntLong.h"
#import "OWSIdentityManager.h"
#import "NSDate+OWS.h"
#import "TSAccountManager.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import "NSObject+Casting.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

#define LKMessageIDCollection @"LKMessageIDCollection"

@implementation OWSPrimaryStorage (Loki)

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

@end
