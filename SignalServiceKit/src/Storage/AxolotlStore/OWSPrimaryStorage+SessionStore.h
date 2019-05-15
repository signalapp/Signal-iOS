//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage.h"
#import <AxolotlKit/SessionStore.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (SessionStore) <SessionStore>

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
                   transaction:(YapDatabaseReadTransaction *)transaction;

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier transaction:(YapDatabaseReadTransaction *)transaction;

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
         transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
            transaction:(YapDatabaseReadTransaction *)transaction;

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier
                        transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier
                         transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Debug

- (void)resetSessionStore:(YapDatabaseReadWriteTransaction *)transaction;

#if DEBUG
- (void)snapshotSessionStore:(YapDatabaseReadWriteTransaction *)transaction;
- (void)restoreSessionStore:(YapDatabaseReadWriteTransaction *)transaction;
#endif

- (void)printAllSessions;

// MARK: - SessionStore methods. Prefer to use the strongly typed `transaction:` flavors above instead.

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
               protocolContext:(nullable id)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier
                protocolContext:(nullable id)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
     protocolContext:(nullable id)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
        protocolContext:(nullable id)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                protocolContext:(nullable id)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier
                    protocolContext:(nullable id)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier
                     protocolContext:(nullable id)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

@end

NS_ASSUME_NONNULL_END
