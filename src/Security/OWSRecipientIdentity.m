//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN
/**
 * Record for a recipients identity key and some meta data around it used to make trust decisions.
 *
 * NOTE: Instances of this class MUST only be retrieved/persisted via it's internal `dbConnection`,
 *       which makes some special accomodations to enforce consistency.
 */
@implementation OWSRecipientIdentity

- (instancetype)initWithRecipientId:(NSString *)recipientId
                        identityKey:(NSData *)identityKey
                    isFirstKnownKey:(BOOL)isFirstKnownKey
                          createdAt:(NSDate *)createdAt
             approvedForBlockingUse:(BOOL)approvedForBlockingUse
          approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse
{
    self = [super initWithUniqueId:recipientId];
    if (!self) {
        return self;
    }
    
    _recipientId = recipientId;
    _identityKey = identityKey;
    _isFirstKnownKey = isFirstKnownKey;
    _createdAt = createdAt;
    _approvedForBlockingUse = approvedForBlockingUse;
    _approvedForNonBlockingUse = approvedForNonBlockingUse;
    _wasSeen = NO;
    
    return self;
}

- (void)markAsSeen
{
    _wasSeen = YES;
}

/**
 * Override to disable the object cache to better enforce transaction semantics on the store.
 * Note that it's still technically possible to access this collection from a different collection,
 * but that should be considered a bug.
 */
+ (YapDatabaseConnection *)dbConnection
{
    static dispatch_once_t onceToken;
    static YapDatabaseConnection *sharedDBConnection;
    dispatch_once(&onceToken, ^{
        sharedDBConnection = [TSStorageManager sharedManager].newDatabaseConnection;
        sharedDBConnection.objectCacheEnabled = NO;
        sharedDBConnection.permittedTransactions = YDB_AnySyncTransaction;
    });
    
    return sharedDBConnection;
}

#pragma mark - debug

+ (void)printAllIdentities
{
    DDLogInfo(@"%@ ### All Recipient Identities ###", self.tag);
    __block int count = 0;
    [self enumerateCollectionObjectsUsingBlock:^(id obj, BOOL *stop) {
        count++;
        if (![obj isKindOfClass:[self class]]) {
            DDLogError(@"%@ unexpected object in collection: %@", self.tag, obj);
            OWSAssert(NO);
            return;
        }
        OWSRecipientIdentity *recipientIdentity = (OWSRecipientIdentity *)obj;

        DDLogInfo(@"%@ Identity %d: %@", self.tag, count, recipientIdentity.debugDescription);
    }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
