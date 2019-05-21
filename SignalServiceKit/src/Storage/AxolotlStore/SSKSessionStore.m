//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKSessionStore.h"
#import "OWSFileSystem.h"
#import "SSKEnvironment.h"
#import "YapDatabaseTransaction+OWS.h"
#import <AxolotlKit/SessionRecord.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSPrimaryStorageSessionStoreCollection = @"TSStorageManagerSessionStoreCollection";

@interface SSKSessionStore ()

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@end

@implementation SSKSessionStore

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:OWSPrimaryStorageSessionStoreCollection];

    return self;
}

#pragma mark -

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
               protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    return [self loadSession:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
                   transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    OWSAssertDebug(deviceId >= 0);

    NSDictionary *_Nullable dictionary = [self.keyValueStore getObject:contactIdentifier transaction:transaction];

    SessionRecord *record;

    if (dictionary) {
        record = [dictionary objectForKey:@(deviceId)];
    }

    if (record == nil) {
        return [SessionRecord new];
    }

    return record;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    return [self subDevicesSessions:contactIdentifier transaction:transaction];
}

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    // Deprecated. We aren't currently using this anywhere, but it's "required" by the SessionStore protocol.
    // If we are going to start using it I'd want to re-verify it works as intended.
    OWSFailDebug(@"subDevicesSessions is deprecated");

    NSDictionary *_Nullable dictionary = [self.keyValueStore getObject:contactIdentifier transaction:transaction];

    return dictionary ? dictionary.allKeys : @[];
}
#pragma clang diagnostic pop

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
     protocolContext:protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    [self storeSession:contactIdentifier deviceId:deviceId session:session transaction:transaction];
}

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
         transaction:(SDSAnyWriteTransaction *)transaction
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

    NSDictionary *immutableDictionary = [self.keyValueStore getObject:contactIdentifier transaction:transaction];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary setObject:session forKey:@(deviceId)];


    [self.keyValueStore setObject:[dictionary copy] key:contactIdentifier transaction:transaction];
}

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
        protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    return [self containsSession:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
            transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    OWSAssertDebug(deviceId >= 0);

    return [self loadSession:contactIdentifier deviceId:deviceId transaction:transaction].sessionState.hasSenderChain;
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                protocolContext:(nullable id)protocolContext
{

    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    [self deleteSessionForContact:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                    transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);
    OWSAssertDebug(deviceId >= 0);

    OWSLogInfo(@"deleting session for contact: %@ device: %d", contactIdentifier, deviceId);

    NSDictionary *immutableDictionary = [self.keyValueStore getObject:contactIdentifier transaction:transaction];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary removeObjectForKey:@(deviceId)];

    [self.keyValueStore setObject:[dictionary copy] key:contactIdentifier transaction:transaction];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    [self deleteAllSessionsForContact:contactIdentifier transaction:transaction];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);

    OWSLogInfo(@"deleting all sessions for contact:%@", contactIdentifier);

    [self.keyValueStore removeValueForKey:contactIdentifier transaction:transaction];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier protocolContext:(nullable id)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = protocolContext;

    [self archiveAllSessionsForContact:contactIdentifier transaction:transaction];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(contactIdentifier.length > 0);

    OWSLogInfo(@"archiving all sessions for contact: %@", contactIdentifier);

    __block NSDictionary<NSNumber *, SessionRecord *> *sessionRecords =
        [self.keyValueStore getObject:contactIdentifier transaction:transaction];

    for (id deviceId in sessionRecords) {
        id object = sessionRecords[deviceId];
        if (![object isKindOfClass:[SessionRecord class]]) {
            OWSFailDebug(@"Unexpected object in session dict: %@", [object class]);
            continue;
        }

        SessionRecord *sessionRecord = (SessionRecord *)object;
        [sessionRecord archiveCurrentState];
    }

    [self.keyValueStore setObject:sessionRecords key:contactIdentifier transaction:transaction];
}

#pragma mark - debug

- (void)resetSessionStore:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogWarn(@"resetting session store");

    [self.keyValueStore removeAllWithTransaction:transaction];
}

- (void)printAllSessionsWithTransaction:(SDSAnyReadTransaction *)transaction;
{
    if (!transaction.transitional_yapReadTransaction) {
        OWSFailDebug(@"GRDB TODO");
        return;
    }
    NSString *tag = @"[OWSPrimaryStorage (SessionStore)]";
    OWSLogDebug(@"%@ All Sessions:", tag);
    [transaction.transitional_yapReadTransaction
        enumerateKeysAndObjectsInCollection:OWSPrimaryStorageSessionStoreCollection
                                 usingBlock:^(
                                     NSString *_Nonnull key, id _Nonnull deviceSessionsObject, BOOL *_Nonnull stop) {
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
}

#if DEBUG
- (NSString *)snapshotFilePath
{
    // Prefix name with period "." so that backups will ignore these snapshots.
    NSString *dirPath = [OWSFileSystem appDocumentDirectoryPath];
    return [dirPath stringByAppendingPathComponent:@".session-snapshot"];
}

- (void)snapshotSessionStore:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (!transaction.transitional_yapWriteTransaction) {
        OWSFailDebug(@"GRDB TODO");
        return;
    }
    [transaction.transitional_yapWriteTransaction snapshotCollection:OWSPrimaryStorageSessionStoreCollection
                                                    snapshotFilePath:self.snapshotFilePath];
}

- (void)restoreSessionStore:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    if (!transaction.transitional_yapWriteTransaction) {
        OWSFailDebug(@"GRDB TODO");
        return;
    }
    [transaction.transitional_yapWriteTransaction restoreSnapshotOfCollection:OWSPrimaryStorageSessionStoreCollection
                                                             snapshotFilePath:self.snapshotFilePath];
}
#endif

@end

NS_ASSUME_NONNULL_END
