//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SSKSessionStore.h"
#import "OWSFileSystem.h"
#import "SSKEnvironment.h"
#import <AxolotlKit/SessionRecord.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSKSessionStore ()

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@end

#pragma mark -

@implementation SSKSessionStore

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:@"TSStorageManagerSessionStoreCollection"];

    return self;
}

- (OWSAccountIdFinder *)accountIdFinder
{
    return [OWSAccountIdFinder new];
}

#pragma mark -

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
               protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);
    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;

    return [self loadSessionForAccountId:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (SessionRecord *)loadSessionForAddress:(SignalServiceAddress *)address
                                deviceId:(int)deviceId
                             transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(deviceId >= 0);

    NSString *accountId = [self.accountIdFinder ensureAccountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId);

    return [self loadSessionForAccountId:accountId deviceId:deviceId transaction:transaction];
}

- (SessionRecord *)loadSessionForAccountId:(NSString *)accountId
                                  deviceId:(int)deviceId
                               transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);
    OWSAssertDebug(deviceId > 0);
    OWSAssertDebug([transaction isKindOfClass:[SDSAnyReadTransaction class]]);

    NSDictionary *_Nullable dictionary = [self.keyValueStore getObjectForKey:accountId transaction:transaction];

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
- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier
                protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);
    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;

    return [self subDevicesSessionsForAccountId:contactIdentifier transaction:transaction];
}

- (NSArray *)subDevicesSessionsForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid > 0);

    NSString *accountId = [self.accountIdFinder accountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId.length > 0);

    return [self subDevicesSessionsForAccountId:accountId transaction:transaction];
}

- (NSArray *)subDevicesSessionsForAccountId:(NSString *)accountId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);

    // Deprecated. We aren't currently using this anywhere, but it's "required" by the SessionStore protocol.
    // If we are going to start using it I'd want to re-verify it works as intended.
    OWSFailDebug(@"subDevicesSessions is deprecated");

    NSDictionary *_Nullable dictionary = [self.keyValueStore getObjectForKey:accountId transaction:transaction];

    return dictionary ? dictionary.allKeys : @[];
}
#pragma clang diagnostic pop

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
     protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = (SDSAnyWriteTransaction *)protocolContext;

    [self storeSessionForAccountId:contactIdentifier deviceId:deviceId session:session transaction:transaction];
}

- (void)storeSession:(SessionRecord *)session
          forAddress:(SignalServiceAddress *)address
            deviceId:(int)deviceId
         transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid > 0);

    NSString *accountId = [self.accountIdFinder ensureAccountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId.length > 0);

    [self storeSessionForAccountId:accountId deviceId:deviceId session:session transaction:transaction];
}

- (void)storeSessionForAccountId:(NSString *)accountId
                        deviceId:(int)deviceId
                         session:(SessionRecord *)session
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);
    OWSAssertDebug(deviceId >= 0);

    // We need to ensure subsequent usage of this SessionRecord does not consider this session as "fresh". Normally this
    // is achieved by marking things as "not fresh" at the point of deserialization - when we fetch a SessionRecord from
    // YapDB (initWithCoder:). However, because YapDB has an object cache, rather than fetching/deserializing, it's
    // possible we'd get back *this* exact instance of the object (which, at this point, is still potentially "fresh"),
    // thus we explicitly mark this instance as "unfresh", any time we save.
    // NOTE: this may no longer be necessary now that we have a non-caching session db connection.
    [session markAsUnFresh];

    NSDictionary *immutableDictionary = [self.keyValueStore getObjectForKey:accountId transaction:transaction];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary setObject:session forKey:@(deviceId)];

    [self.keyValueStore setObject:[dictionary copy] key:accountId transaction:transaction];
}

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
        protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyReadTransaction class]]);
    SDSAnyReadTransaction *transaction = (SDSAnyReadTransaction *)protocolContext;

    return [self containsSessionForAccountId:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (BOOL)containsSessionForAddress:(SignalServiceAddress *)address
                         deviceId:(int)deviceId
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(deviceId >= 0);

    NSString *accountId = [self.accountIdFinder ensureAccountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId.length > 0);

    return [self containsSessionForAccountId:accountId deviceId:deviceId transaction:transaction];
}

- (BOOL)containsSessionForAccountId:(NSString *)accountId
                           deviceId:(int)deviceId
                        transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);
    OWSAssertDebug(deviceId >= 0);

    return
        [self loadSessionForAccountId:accountId deviceId:deviceId transaction:transaction].sessionState.hasSenderChain;
}

- (nullable NSNumber *)maxSessionSenderChainKeyIndexForAccountId:(NSString *)accountId
                                                     transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);
    OWSAssertDebug([transaction isKindOfClass:[SDSAnyReadTransaction class]]);

    NSNumber *_Nullable result = nil;
    NSDictionary *_Nullable dictionary = [self.keyValueStore getObjectForKey:accountId transaction:transaction];
    for (id value in dictionary.allValues) {
        if (![value isKindOfClass:[SessionRecord class]]) {
            OWSLogVerbose(@"Unexpected value: %@", value);
            OWSFailDebug(@"Unexpected value.");
            continue;
        }
        SessionRecord *record = (SessionRecord *)value;
        if (SSKDebugFlags.verboseSignalRecipientLogging) {
            OWSLogInfo(@"Record hasSenderChain: %d.", record.sessionState.hasSenderChain);
        }
        if (record.sessionState.hasSenderChain) {
            int index = record.sessionState.senderChainKey.index;
            if (SSKDebugFlags.verboseSignalRecipientLogging) {
                OWSLogInfo(@"Record index: %d.", index);
            }
            if (result == nil || result.intValue < index) {
                result = @(index);
            }
        }
    }
    return result;
}

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = (SDSAnyWriteTransaction *)protocolContext;

    OWSLogInfo(@"deleting session for contact: %@ device: %d", contactIdentifier, deviceId);

    [self deleteSessionForAccountId:contactIdentifier deviceId:deviceId transaction:transaction];
}

- (void)deleteSessionForAddress:(SignalServiceAddress *)address
                       deviceId:(int)deviceId
                    transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(deviceId >= 0);

    OWSLogInfo(@"deleting session for address: %@ device: %d", address, deviceId);

    NSString *accountId = [self.accountIdFinder ensureAccountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId.length > 0);

    return [self deleteSessionForAccountId:accountId deviceId:deviceId transaction:transaction];
}

- (void)deleteSessionForAccountId:(NSString *)accountId
                         deviceId:(int)deviceId
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);
    OWSAssertDebug(deviceId >= 0);

    OWSLogInfo(@"deleting session for accountId: %@ device: %d", accountId, deviceId);

    NSDictionary *immutableDictionary = [self.keyValueStore getObjectForKey:accountId transaction:transaction];

    NSMutableDictionary *dictionary
        = (immutableDictionary ? [immutableDictionary mutableCopy] : [NSMutableDictionary new]);

    [dictionary removeObjectForKey:@(deviceId)];

    [self.keyValueStore setObject:[dictionary copy] key:accountId transaction:transaction];
}

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier
                    protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = (SDSAnyWriteTransaction *)protocolContext;

    [self deleteAllSessionsForAccountId:contactIdentifier transaction:transaction];
}

- (void)deleteAllSessionsForAddress:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    NSString *accountId = [self.accountIdFinder ensureAccountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId.length > 0);

    [self deleteAllSessionsForAccountId:accountId transaction:transaction];
}

- (void)deleteAllSessionsForAccountId:(NSString *)accountId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);

    OWSLogInfo(@"deleting all sessions for contact: %@", accountId);

    [self.keyValueStore removeValueForKey:accountId transaction:transaction];
}

- (void)archiveSessionForAddress:(SignalServiceAddress *)address
                        deviceId:(int)deviceId
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(deviceId >= 0);

    NSString *accountId = [self.accountIdFinder ensureAccountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId.length > 0);

    [self archiveSessionForAccountId:accountId deviceId:deviceId transaction:transaction];
}

- (void)archiveSessionForAccountId:(NSString *)accountId
                          deviceId:(int)deviceId
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);

    OWSLogInfo(@"Archiving session for contact: %@ device: %d", accountId, deviceId);

    SessionRecord *sessionRecord = [self loadSessionForAccountId:accountId deviceId:deviceId transaction:transaction];
    [sessionRecord archiveCurrentState];
    [self storeSessionForAccountId:accountId deviceId:deviceId session:sessionRecord transaction:transaction];
}

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier
                     protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
{
    OWSAssertDebug([protocolContext isKindOfClass:[SDSAnyWriteTransaction class]]);
    SDSAnyWriteTransaction *transaction = (SDSAnyWriteTransaction *)protocolContext;

    [self archiveAllSessionsForAccountId:contactIdentifier transaction:transaction];
}

- (void)archiveAllSessionsForAddress:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);

    NSString *accountId = [self.accountIdFinder ensureAccountIdForAddress:address transaction:transaction];
    OWSAssertDebug(accountId.length > 0);

    [self archiveAllSessionsForAccountId:accountId transaction:transaction];
}

- (void)archiveAllSessionsForAccountId:(NSString *)accountId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(accountId.length > 0);

    OWSLogInfo(@"archiving all sessions for contact: %@", accountId);

    __block NSDictionary<NSNumber *, SessionRecord *> *sessionRecords =
        [self.keyValueStore getObjectForKey:accountId transaction:transaction];

    for (id deviceId in sessionRecords) {
        id object = sessionRecords[deviceId];
        if (![object isKindOfClass:[SessionRecord class]]) {
            OWSFailDebug(@"Unexpected object in session dict: %@", [object class]);
            continue;
        }

        SessionRecord *sessionRecord = (SessionRecord *)object;
        [sessionRecord archiveCurrentState];
    }

    [self.keyValueStore setObject:sessionRecords key:accountId transaction:transaction];
}

#pragma mark - debug

- (void)resetSessionStore:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogWarn(@"resetting session store");

    [self.keyValueStore removeAllWithTransaction:transaction];
}

- (void)printAllSessionsWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSLogDebug(@"All Sessions.");
    [self.keyValueStore
        enumerateKeysAndObjectsWithTransaction:transaction
                                         block:^(NSString *key, id value, BOOL *stop) {
                                             if (![value isKindOfClass:[NSDictionary class]]) {
                                                 OWSFailDebug(@"Unexpected type: %@ in collection.", [value class]);
                                                 return;
                                             }
                                             NSDictionary *deviceSessions = (NSDictionary *)value;

                                             OWSLogDebug(@"     Sessions for recipient: %@", key);
                                             [deviceSessions enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key,
                                                 id _Nonnull sessionRecordObject,
                                                 BOOL *_Nonnull stop) {
                                                 if (![sessionRecordObject isKindOfClass:[SessionRecord class]]) {
                                                     OWSFailDebug(@"Unexpected type: %@ in collection.",
                                                         [sessionRecordObject class]);
                                                     return;
                                                 }
                                                 SessionRecord *sessionRecord = (SessionRecord *)sessionRecordObject;
                                                 SessionState *activeState = [sessionRecord sessionState];
                                                 NSArray<SessionState *> *previousStates =
                                                     [sessionRecord previousSessionStates];
                                                 OWSLogDebug(
                                                     @"         Device: %@ SessionRecord: %@ activeSessionState: "
                                                     @"%@ previousSessionStates: %@",
                                                     key,
                                                     sessionRecord,
                                                     activeState,
                                                     previousStates);
                                             }];
                                         }];
}

@end

NS_ASSUME_NONNULL_END
