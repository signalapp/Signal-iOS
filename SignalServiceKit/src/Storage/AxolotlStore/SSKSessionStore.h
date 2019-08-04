//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/SessionStore.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;

extern NSString *const OWSPrimaryStorageSessionStoreCollection;

@interface SSKSessionStore : NSObject <SessionStore>

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
                   transaction:(SDSAnyReadTransaction *)transaction;

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier transaction:(SDSAnyReadTransaction *)transaction;

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
         transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
            transaction:(SDSAnyReadTransaction *)transaction;

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                    transaction:(SDSAnyWriteTransaction *)transaction;

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier transaction:(SDSAnyWriteTransaction *)transaction;

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier transaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Debug

- (void)resetSessionStore:(SDSAnyWriteTransaction *)transaction;

- (void)printAllSessionsWithTransaction:(SDSAnyReadTransaction *)transaction;

// MARK: - SessionStore methods. Prefer to use the strongly typed `transaction:` flavors above instead.

- (SessionRecord *)loadSession:(NSString *)contactIdentifier
                      deviceId:(int)deviceId
               protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (NSArray *)subDevicesSessions:(NSString *)contactIdentifier
                protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)storeSession:(NSString *)contactIdentifier
            deviceId:(int)deviceId
             session:(SessionRecord *)session
     protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (BOOL)containsSession:(NSString *)contactIdentifier
               deviceId:(int)deviceId
        protocolContext:(nullable id<SPKProtocolReadContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)deleteSessionForContact:(NSString *)contactIdentifier
                       deviceId:(int)deviceId
                protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)deleteAllSessionsForContact:(NSString *)contactIdentifier
                    protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier
                     protocolContext:(nullable id<SPKProtocolWriteContext>)protocolContext
    DEPRECATED_MSG_ATTRIBUTE("use the strongly typed `transaction:` flavor instead");

@end

NS_ASSUME_NONNULL_END
