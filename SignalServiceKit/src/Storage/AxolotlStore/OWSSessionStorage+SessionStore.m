//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSessionStorage+SessionStore.h"
#import <AxolotlKit/SessionRecord.h>
#import <YapDatabase/YapDatabase.h>

NSString *const OWSSessionStorageSessionStoreCollection = @"TSStorageManagerSessionStoreCollection";

void AssertIsOnSessionStoreQueue()
{
#ifdef DEBUG
    if (@available(iOS 10.0, *)) {
        dispatch_assert_queue([OWSDispatch sessionStoreQueue]);
    } // else, skip assert as it's a development convenience.
#endif
}

@implementation OWSSessionStorage (SessionStore)

#pragma mark - SessionStore

- (SessionRecord *)loadSession:(NSString *)contactIdentifier deviceId:(int)deviceId
{
    AssertIsOnSessionStoreQueue();

    __block NSDictionary *dictionary;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        dictionary = [transaction objectForKey:contactIdentifier inCollection:OWSSessionStorageSessionStoreCollection];
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
    OWSFail(@"%@ subDevicesSessions is deprecated", self.logTag);
    AssertIsOnSessionStoreQueue();

    __block NSDictionary *dictionary;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        dictionary = [transaction objectForKey:contactIdentifier inCollection:OWSSessionStorageSessionStoreCollection];
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
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        immutableDictionary =
            [transaction objectForKey:contactIdentifier inCollection:OWSSessionStorageSessionStoreCollection];
    }];

    NSMutableDictionary *dictionary = [immutableDictionary mutableCopy];

    if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
    }

    [dictionary setObject:session forKey:@(deviceId)];

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:[dictionary copy]
                        forKey:contactIdentifier
                  inCollection:OWSSessionStorageSessionStoreCollection];
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
        @"[OWSSessionStorage (SessionStore)] deleting session for contact: %@ device: %d", contactIdentifier, deviceId);

    __block NSDictionary *immutableDictionary;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        immutableDictionary =
            [transaction objectForKey:contactIdentifier inCollection:OWSSessionStorageSessionStoreCollection];
    }];
    NSMutableDictionary *dictionary = [immutableDictionary mutableCopy];

    if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
    }

    [dictionary removeObjectForKey:@(deviceId)];

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:[dictionary copy]
                        forKey:contactIdentifier
                  inCollection:OWSSessionStorageSessionStoreCollection];
    }];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier
{
    AssertIsOnSessionStoreQueue();
    DDLogInfo(@"[OWSSessionStorage (SessionStore)] deleting all sessions for contact:%@", contactIdentifier);

    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeObjectForKey:contactIdentifier inCollection:OWSSessionStorageSessionStoreCollection];
    }];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier
{
    AssertIsOnSessionStoreQueue();

    DDLogInfo(@"[OWSSessionStorage (SessionStore)] archiving all sessions for contact: %@", contactIdentifier);

    __block NSDictionary<NSNumber *, SessionRecord *> *sessionRecords;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        sessionRecords =
            [transaction objectForKey:contactIdentifier inCollection:OWSSessionStorageSessionStoreCollection];

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
                  inCollection:OWSSessionStorageSessionStoreCollection];
    }];
}

#pragma mark - debug

- (void)resetSessionStore
{
    // TODO: AssertIsOnSessionStoreQueue();?

    DDLogWarn(@"%@ resetting session store", self.logTag);
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction removeAllObjectsInCollection:OWSSessionStorageSessionStoreCollection];
    }];
}

- (void)printAllSessions
{
    AssertIsOnSessionStoreQueue();

    NSString *tag = @"[OWSSessionStorage (SessionStore)]";
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        DDLogDebug(@"%@ All Sessions:", tag);
        [transaction
            enumerateKeysAndObjectsInCollection:OWSSessionStorageSessionStoreCollection
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

@end
