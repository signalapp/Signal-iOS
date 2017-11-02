//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+SessionStore.h"
#import <AxolotlKit/SessionRecord.h>

NSString *const TSStorageManagerSessionStoreCollection = @"TSStorageManagerSessionStoreCollection";
NSString *const kSessionStoreDBConnectionKey = @"kSessionStoreDBConnectionKey";

void AssertIsOnSessionStoreQueue()
{
#ifdef DEBUG
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(10, 0)) {
        dispatch_assert_queue([OWSDispatch sessionStoreQueue]);
    } // else, skip assert as it's a development convenience.
#endif
}

@implementation TSStorageManager (SessionStore)

/**
 * Special purpose dbConnection which disables the object cache to better enforce transaction semantics on the store.
 * Note that it's still technically possible to access this collection from a different collection,
 * but that should be considered a bug.
 */
+ (YapDatabaseConnection *)sessionDBConnection
{
    static dispatch_once_t onceToken;
    static YapDatabaseConnection *sessionDBConnection;
    dispatch_once(&onceToken, ^{
        sessionDBConnection = [TSStorageManager sharedManager].newDatabaseConnection;
        sessionDBConnection.objectCacheEnabled = NO;
#if DEBUG
        sessionDBConnection.permittedTransactions = YDB_AnySyncTransaction;
#endif
    });

    return sessionDBConnection;
}

- (YapDatabaseConnection *)sessionDBConnection
{
    return [[self class] sessionDBConnection];
}

#pragma mark - SessionStore

- (SessionRecord *)loadSession:(NSString *)contactIdentifier deviceId:(int)deviceId
{
    AssertIsOnSessionStoreQueue();

    __block NSDictionary *dictionary;
    [self.sessionDBConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        dictionary = [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
    }];

    SessionRecord *record;

    if (dictionary) {
        record = [dictionary objectForKey:@(deviceId)];
    }

    if (!record) {
        return [SessionRecord new];
    }

    return record;
}

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier
{
    // Deprecated. We aren't currently using this anywhere, but it's "required" by the SessionStore protocol.
    // If we are going to start using it I'd want to re-verify it works as intended.
    OWSFail(@"%@ subDevicesSessions is deprecated", self.tag);
    AssertIsOnSessionStoreQueue();

    __block NSDictionary *dictionary;
    [self.sessionDBConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        dictionary = [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
    }];

    return dictionary ? dictionary.allKeys : @[];
}

- (void)storeSession:(NSString *)contactIdentifier deviceId:(int)deviceId session:(SessionRecord *)session
{
    AssertIsOnSessionStoreQueue();

    // We need to ensure subsequent usage of this SessionRecord does not consider this session as "fresh". Normally this
    // is achieved by marking things as "not fresh" at the point of deserialization - when we fetch a SessionRecord from
    // YapDB (initWithCoder:). However, because YapDB has an object cache, rather than fetching/deserializing, it's
    // possible we'd get back *this* exact instance of the object (which, at this point, is still potentially "fresh"),
    // thus we explicitly mark this instance as "unfresh", any time we save.
    // NOTE: this may no longer be necessary now that we have a non-caching session db connection.
    [session markAsUnFresh];

    __block NSDictionary *immutableDictionary;
    [self.sessionDBConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        immutableDictionary =
            [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
    }];

    NSMutableDictionary *dictionary = [immutableDictionary mutableCopy];

    if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
    }

    [dictionary setObject:session forKey:@(deviceId)];

    [self.sessionDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:[dictionary copy]
                        forKey:contactIdentifier
                  inCollection:TSStorageManagerSessionStoreCollection];
    }];
}

- (BOOL)containsSession:(NSString *)contactIdentifier deviceId:(int)deviceId
{
    AssertIsOnSessionStoreQueue();

    return [self loadSession:contactIdentifier deviceId:deviceId].sessionState.hasSenderChain;
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier deviceId:(int)deviceId
{
    AssertIsOnSessionStoreQueue();
    DDLogInfo(
        @"[TSStorageManager (SessionStore)] deleting session for contact: %@ device: %d", contactIdentifier, deviceId);

    __block NSDictionary *immutableDictionary;
    [self.sessionDBConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        immutableDictionary =
            [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
    }];
    NSMutableDictionary *dictionary = [immutableDictionary mutableCopy];

    if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
    }

    [dictionary removeObjectForKey:@(deviceId)];

    [self.sessionDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:[dictionary copy]
                        forKey:contactIdentifier
                  inCollection:TSStorageManagerSessionStoreCollection];
    }];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier
{
    AssertIsOnSessionStoreQueue();
    DDLogInfo(@"[TSStorageManager (SessionStore)] deleting all sessions for contact:%@", contactIdentifier);

    [self.sessionDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeObjectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
    }];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier
{
    AssertIsOnSessionStoreQueue();

    DDLogInfo(@"[TSStorageManager (SessionStore)] archiving all sessions for contact: %@", contactIdentifier);

    __block NSDictionary<NSNumber *, SessionRecord *> *sessionRecords;
    [self.sessionDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        sessionRecords =
            [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];

        for (id deviceId in sessionRecords) {
            id object = sessionRecords[deviceId];
            if (![object isKindOfClass:[SessionRecord class]]) {
                OWSFail(@"Unexpected object in session dict: %@", object);
                continue;
            }

            SessionRecord *sessionRecord = (SessionRecord *)object;
            [sessionRecord archiveCurrentState];
        }

        [transaction setObject:sessionRecords
                        forKey:contactIdentifier
                  inCollection:TSStorageManagerSessionStoreCollection];
    }];
}

#pragma mark - debug

- (void)resetSessionStore
{
    DDLogWarn(@"%@ resetting session store", self.tag);
    [self.sessionDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeAllObjectsInCollection:TSStorageManagerSessionStoreCollection];
    }];
}

- (void)printAllSessions
{
    AssertIsOnSessionStoreQueue();

    NSString *tag = @"[TSStorageManager (SessionStore)]";
    [self.sessionDBConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        DDLogDebug(@"%@ All Sessions:", tag);
        [transaction
            enumerateKeysAndObjectsInCollection:TSStorageManagerSessionStoreCollection
                                     usingBlock:^(NSString *_Nonnull key,
                                         id _Nonnull deviceSessionsObject,
                                         BOOL *_Nonnull stop) {
                                         if (![deviceSessionsObject isKindOfClass:[NSDictionary class]]) {
                                             OWSFail(
                                                 @"%@ Unexpected type: %@ in collection.", tag, deviceSessionsObject);
                                             return;
                                         }
                                         NSDictionary *deviceSessions = (NSDictionary *)deviceSessionsObject;

                                         DDLogDebug(@"%@     Sessions for recipient: %@", tag, key);
                                         [deviceSessions enumerateKeysAndObjectsUsingBlock:^(
                                             id _Nonnull key, id _Nonnull sessionRecordObject, BOOL *_Nonnull stop) {
                                             if (![sessionRecordObject isKindOfClass:[SessionRecord class]]) {
                                                 OWSFail(@"%@ Unexpected type: %@ in collection.",
                                                     tag,
                                                     sessionRecordObject);
                                                 return;
                                             }
                                             SessionRecord *sessionRecord = (SessionRecord *)sessionRecordObject;
                                             SessionState *activeState = [sessionRecord sessionState];
                                             NSArray<SessionState *> *previousStates =
                                                 [sessionRecord previousSessionStates];
                                             DDLogDebug(@"%@         Device: %@ SessionRecord: %@ activeSessionState: "
                                                        @"%@ previousSessionStates: %@",
                                                 tag,
                                                 key,
                                                 sessionRecord,
                                                 activeState,
                                                 previousStates);
                                         }];
                                     }];
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
