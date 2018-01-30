//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFileSystem.h"
#import "TSStorageManager+SessionStore.h"
#import "YapDatabaseConnection+OWS.h"
#import <AxolotlKit/SessionRecord.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSStorageManagerSessionStoreCollection = @"TSStorageManagerSessionStoreCollection";
NSString *const kSessionStoreDBConnectionKey = @"kSessionStoreDBConnectionKey";

@implementation TSStorageManager (SessionStore)

/**
 * Special purpose dbConnection which disables the object cache to better enforce transaction semantics on the store.
 * Note that it's still technically possible to access this collection from a different collection,
 * but that should be considered a bug.
 */
+ (YapDatabaseConnection *)protocolStoreDBConnection
{
    static dispatch_once_t onceToken;
    static YapDatabaseConnection *protocolStoreDBConnection;
    dispatch_once(&onceToken, ^{
        protocolStoreDBConnection = [TSStorageManager sharedManager].newDatabaseConnection;
        protocolStoreDBConnection.objectCacheEnabled = NO;
#if DEBUG
        protocolStoreDBConnection.permittedTransactions = YDB_AnySyncTransaction;
#endif
    });

    return protocolStoreDBConnection;
}

// TODO: Audit usage of this connection.
- (YapDatabaseConnection *)protocolStoreDBConnection
{
    return [[self class] protocolStoreDBConnection];
}

#pragma mark - SessionStore

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
               protocolContext:(nullable id)protocolContext
{
    OWSAssert(contactIdentifier.length > 0);
    OWSAssert(deviceId >= 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    NSDictionary *_Nullable dictionary =
        [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];

    SessionRecord *record;

    if (dictionary) {
        record = [dictionary objectForKey:@(deviceId)];
    }

    if (!record) {
        return [SessionRecord new];
    }

    return record;
}

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssert(contactIdentifier.length > 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    // Deprecated. We aren't currently using this anywhere, but it's "required" by the SessionStore protocol.
    // If we are going to start using it I'd want to re-verify it works as intended.
    OWSFail(@"%@ subDevicesSessions is deprecated", self.logTag);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    NSDictionary *_Nullable dictionary =
        [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];

    return dictionary ? dictionary.allKeys : @[];
}

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
     protocolContext:protocolContext
{
    OWSAssert(contactIdentifier.length > 0);
    OWSAssert(deviceId >= 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    // We need to ensure subsequent usage of this SessionRecord does not consider this session as "fresh". Normally this
    // is achieved by marking things as "not fresh" at the point of deserialization - when we fetch a SessionRecord from
    // YapDB (initWithCoder:). However, because YapDB has an object cache, rather than fetching/deserializing, it's
    // possible we'd get back *this* exact instance of the object (which, at this point, is still potentially "fresh"),
    // thus we explicitly mark this instance as "unfresh", any time we save.
    // NOTE: this may no longer be necessary now that we have a non-caching session db connection.
    [session markAsUnFresh];

    NSDictionary *immutableDictionary =
        [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary setObject:session forKey:@(deviceId)];

    [transaction setObject:[dictionary copy]
                    forKey:contactIdentifier
              inCollection:TSStorageManagerSessionStoreCollection];
}

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
        protocolContext:(nullable id)protocolContext
{
    OWSAssert(contactIdentifier.length > 0);
    OWSAssert(deviceId >= 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    return [self loadSession:contactIdentifier deviceId:deviceId protocolContext:protocolContext]
        .sessionState.hasSenderChain;
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                protocolContext:(nullable id)protocolContext
{
    OWSAssert(contactIdentifier.length > 0);
    OWSAssert(deviceId >= 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    DDLogInfo(
        @"[TSStorageManager (SessionStore)] deleting session for contact: %@ device: %d", contactIdentifier, deviceId);

    NSDictionary *immutableDictionary =
        [transaction objectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary removeObjectForKey:@(deviceId)];

    [transaction setObject:[dictionary copy]
                    forKey:contactIdentifier
              inCollection:TSStorageManagerSessionStoreCollection];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssert(contactIdentifier.length > 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    DDLogInfo(@"[TSStorageManager (SessionStore)] deleting all sessions for contact:%@", contactIdentifier);

    [transaction removeObjectForKey:contactIdentifier inCollection:TSStorageManagerSessionStoreCollection];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssert(contactIdentifier.length > 0);
    OWSAssert([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);

    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    DDLogInfo(@"[TSStorageManager (SessionStore)] archiving all sessions for contact: %@", contactIdentifier);

    __block NSDictionary<NSNumber *, SessionRecord *> *sessionRecords =
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
}

#pragma mark - debug

- (void)resetSessionStore
{
    DDLogWarn(@"%@ resetting session store", self.logTag);
    [self.protocolStoreDBConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeAllObjectsInCollection:TSStorageManagerSessionStoreCollection];
    }];
}

- (void)printAllSessions
{
    NSString *tag = @"[TSStorageManager (SessionStore)]";
    [self.protocolStoreDBConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
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

#if DEBUG
- (NSString *)snapshotFilePath
{
    // Prefix name with period "." so that backups will ignore these snapshots.
    NSString *dirPath = [OWSFileSystem appDocumentDirectoryPath];
    return [dirPath stringByAppendingPathComponent:@".session-snapshot"];
}

- (void)snapshotSessionStore
{
    [self.protocolStoreDBConnection snapshotCollection:TSStorageManagerSessionStoreCollection
                                      snapshotFilePath:self.snapshotFilePath];
}

- (void)restoreSessionStore
{
    [self.protocolStoreDBConnection restoreSnapshotOfCollection:TSStorageManagerSessionStoreCollection
                                               snapshotFilePath:self.snapshotFilePath];
}
#endif

@end

NS_ASSUME_NONNULL_END
