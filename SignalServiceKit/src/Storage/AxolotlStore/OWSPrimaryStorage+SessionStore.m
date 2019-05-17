//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSFileSystem.h"
#import "SSKEnvironment.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import <AxolotlKit/SessionRecord.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPrimaryStorageSessionStoreCollection = @"TSStorageManagerSessionStoreCollection";
NSString *const kSessionStoreDBConnectionKey = @"kSessionStoreDBConnectionKey";

@implementation OWSPrimaryStorage (SessionStore)

/**
 * Special purpose dbConnection which disables the object cache to better enforce transaction semantics on the store.
 * Note that it's still technically possible to access this collection from a different collection,
 * but that should be considered a bug.
 */
+ (YapDatabaseConnection *)sessionStoreDBConnection
{
    return SSKEnvironment.shared.sessionStoreDBConnection;
}

- (YapDatabaseConnection *)sessionStoreDBConnection
{
    return [[self class] sessionStoreDBConnection];
}

#pragma mark - SessionStore

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
               protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return [self loadSession:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
                   transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    OWSAssertDebug(deviceId >= 0);

    NSDictionary *_Nullable dictionary =
        [transaction objectForKey:contactIdentifier inCollection:OWSPrimaryStorageSessionStoreCollection];

    SessionRecord *record;

    if (dictionary) {
        record = [dictionary objectForKey:@(deviceId)];
    }

    if (!record) {
        return [SessionRecord new];
    }

    return record;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return [self subDevicesSessions:contactIdentifier transaction:transaction];
}

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    // Deprecated. We aren't currently using this anywhere, but it's "required" by the SessionStore protocol.
    // If we are going to start using it I'd want to re-verify it works as intended.
    OWSFailDebug(@"subDevicesSessions is deprecated");

    NSDictionary *_Nullable dictionary =
        [transaction objectForKey:contactIdentifier inCollection:OWSPrimaryStorageSessionStoreCollection];

    return dictionary ? dictionary.allKeys : @[];
}
#pragma clang diagnostic pop

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
     protocolContext:protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    [self storeSession:contactIdentifier deviceId:deviceId session:session transaction:transaction];
}

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
         transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    OWSAssertDebug(deviceId >= 0);

    // We need to ensure subsequent usage of this SessionRecord does not consider this session as "fresh". Normally this
    // is achieved by marking things as "not fresh" at the point of deserialization - when we fetch a SessionRecord from
    // YapDB (initWithCoder:). However, because YapDB has an object cache, rather than fetching/deserializing, it's
    // possible we'd get back *this* exact instance of the object (which, at this point, is still potentially "fresh"),
    // thus we explicitly mark this instance as "unfresh", any time we save.
    // NOTE: this may no longer be necessary now that we have a non-caching session db connection.
    [session markAsUnFresh];

    NSDictionary *immutableDictionary =
        [transaction objectForKey:contactIdentifier inCollection:OWSPrimaryStorageSessionStoreCollection];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary setObject:session forKey:@(deviceId)];

    [transaction setObject:[dictionary copy]
                    forKey:contactIdentifier
              inCollection:OWSPrimaryStorageSessionStoreCollection];
}

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
        protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    return [self containsSession:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
            transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    OWSAssertDebug(deviceId >= 0);

    return [self loadSession:contactIdentifier deviceId:deviceId transaction:transaction].sessionState.hasSenderChain;
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                protocolContext:(nullable id)protocolContext
{

    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    [self deleteSessionForContact:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                    transaction:(nonnull YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    OWSAssertDebug(deviceId >= 0);

    OWSLogInfo(
        @"[OWSPrimaryStorage (SessionStore)] deleting session for contact: %@ device: %d", contactIdentifier, deviceId);

    NSDictionary *immutableDictionary =
        [transaction objectForKey:contactIdentifier inCollection:OWSPrimaryStorageSessionStoreCollection];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary removeObjectForKey:@(deviceId)];

    [transaction setObject:[dictionary copy]
                    forKey:contactIdentifier
              inCollection:OWSPrimaryStorageSessionStoreCollection];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    [self deleteAllSessionsForContact:contactIdentifier transaction:transaction];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier
                        transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);

    OWSLogInfo(@"[OWSPrimaryStorage (SessionStore)] deleting all sessions for contact:%@", contactIdentifier);

    [transaction removeObjectForKey:contactIdentifier inCollection:OWSPrimaryStorageSessionStoreCollection];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;

    [self archiveAllSessionsForContact:contactIdentifier transaction:transaction];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier
                         transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);

    OWSLogInfo(@"[OWSPrimaryStorage (SessionStore)] archiving all sessions for contact: %@", contactIdentifier);

    __block NSDictionary<NSNumber *, SessionRecord *> *sessionRecords =
        [transaction objectForKey:contactIdentifier inCollection:OWSPrimaryStorageSessionStoreCollection];

    for (id deviceId in sessionRecords) {
        id object = sessionRecords[deviceId];
        if (![object isKindOfClass:[SessionRecord class]]) {
            OWSFailDebug(@"Unexpected object in session dict: %@", [object class]);
            continue;
        }

        SessionRecord *sessionRecord = (SessionRecord *)object;
        [sessionRecord archiveCurrentState];
    }

    [transaction setObject:sessionRecords
                    forKey:contactIdentifier
              inCollection:OWSPrimaryStorageSessionStoreCollection];
}

#pragma mark - debug

- (void)resetSessionStore:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogWarn(@"resetting session store");

    [transaction removeAllObjectsInCollection:OWSPrimaryStorageSessionStoreCollection];
}

- (void)printAllSessions
{
    NSString *tag = @"[OWSPrimaryStorage (SessionStore)]";
    [self.sessionStoreDBConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        OWSLogDebug(@"%@ All Sessions:", tag);
        [transaction
            enumerateKeysAndObjectsInCollection:OWSPrimaryStorageSessionStoreCollection
                                     usingBlock:^(NSString *_Nonnull key,
                                         id _Nonnull deviceSessionsObject,
                                         BOOL *_Nonnull stop) {
                                         if (![deviceSessionsObject isKindOfClass:[NSDictionary class]]) {
                                             OWSFailDebug(@"%@ Unexpected type: %@ in collection.",
                                                 tag,
                                                 [deviceSessionsObject class]);
                                             return;
                                         }
                                         NSDictionary *deviceSessions = (NSDictionary *)deviceSessionsObject;

                                         OWSLogDebug(@"%@     Sessions for recipient: %@", tag, key);
                                         [deviceSessions enumerateKeysAndObjectsUsingBlock:^(
                                             id _Nonnull key, id _Nonnull sessionRecordObject, BOOL *_Nonnull stop) {
                                             if (![sessionRecordObject isKindOfClass:[SessionRecord class]]) {
                                                 OWSFailDebug(@"%@ Unexpected type: %@ in collection.",
                                                     tag,
                                                     [sessionRecordObject class]);
                                                 return;
                                             }
                                             SessionRecord *sessionRecord = (SessionRecord *)sessionRecordObject;
                                             SessionState *activeState = [sessionRecord sessionState];
                                             NSArray<SessionState *> *previousStates =
                                                 [sessionRecord previousSessionStates];
                                             OWSLogDebug(@"%@         Device: %@ SessionRecord: %@ activeSessionState: "
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

- (void)snapshotSessionStore:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [transaction snapshotCollection:OWSPrimaryStorageSessionStoreCollection snapshotFilePath:self.snapshotFilePath];
}

- (void)restoreSessionStore:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    [transaction restoreSnapshotOfCollection:OWSPrimaryStorageSessionStoreCollection
                            snapshotFilePath:self.snapshotFilePath];
}
#endif

@end

NS_ASSUME_NONNULL_END
