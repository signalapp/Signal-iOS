//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigration.h"
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigration

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super initWithUniqueId:[self.class migrationId]];
    if (!self) {
        return self;
    }

    _storageManager = storageManager;

    return self;
}

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    if ([propertyKey isEqualToString:@"storageManager"]) {
        return MTLPropertyStorageNone;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
}

+ (NSString *)migrationId
{
    OWSRaiseException(NSInternalInconsistencyException, @"Must override %@ in subclass", NSStringFromSelector(_cmd));
}

+ (NSString *)collection
{
    // We want all subclasses in the same collection
    return @"OWSDatabaseMigration";
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSRaiseException(NSInternalInconsistencyException, @"Must override %@ in subclass", NSStringFromSelector(_cmd));
}

- (void)runUp
{
    [self.storageManager.newDatabaseConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self runUpWithTransaction:transaction];
        }
        completionBlock:^{
            DDLogInfo(@"Completed migration %@", self.uniqueId);
            [self save];
        }];
}

@end

NS_ASSUME_NONNULL_END
