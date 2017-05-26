//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "TSStorageManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSRecipientIdentity ()

@property (atomic) BOOL wasSeen;
@property (atomic) BOOL approvedForBlockingUse;
@property (atomic) BOOL approvedForNonBlockingUse;

@end

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

- (void)updateAsSeen
{
    [self updateWithChangeBlock:^(OWSRecipientIdentity *_Nonnull obj) {
        obj.wasSeen = YES;
    }];
}

- (void)updateWithApprovedForBlockingUse:(BOOL)approvedForBlockingUse
               approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse
{
    // Ensure changes are persisted without clobbering any work done on another thread or instance.
    [self updateWithChangeBlock:^(OWSRecipientIdentity *_Nonnull obj) {
        obj.approvedForBlockingUse = approvedForBlockingUse;
        obj.approvedForNonBlockingUse = approvedForNonBlockingUse;
    }];
}

- (void)updateWithChangeBlock:(void (^)(OWSRecipientIdentity *obj))changeBlock
{
    changeBlock(self);

    [[self class].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSRecipientIdentity *latest = [[self class] fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
        if (latest == nil) {
            [self saveWithTransaction:transaction];
            return;
        }

        changeBlock(latest);
        [latest saveWithTransaction:transaction];
    }];
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
#if DEBUG
        sharedDBConnection.permittedTransactions = YDB_AnySyncTransaction;
#endif
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
