//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/SessionStore.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignalServiceAddress;

@interface SSKSessionStore : NSObject <SessionStore>

- (SessionRecord *)loadSessionForAddress:(SignalServiceAddress *)address
                                deviceId:(int)deviceId
                             transaction:(SDSAnyWriteTransaction *)transaction;

- (NSArray *)subDevicesSessionsForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (void)storeSession:(SessionRecord *)session
          forAddress:(SignalServiceAddress *)address
            deviceId:(int)deviceId
         transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)containsSessionForAddress:(SignalServiceAddress *)address
                         deviceId:(int)deviceId
                      transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)containsSessionForAccountId:(NSString *)accountId
                           deviceId:(int)deviceId
                        transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSNumber *)maxSessionSenderChainKeyIndexForAccountId:(NSString *)accountId
                                                     transaction:(SDSAnyReadTransaction *)transaction;

- (void)deleteSessionForAddress:(SignalServiceAddress *)address
                       deviceId:(int)deviceId
                    transaction:(SDSAnyWriteTransaction *)transaction;

- (void)deleteAllSessionsForAddress:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction;

- (void)archiveSessionForAddress:(SignalServiceAddress *)address
                        deviceId:(int)deviceId
                     transaction:(SDSAnyWriteTransaction *)transaction;

- (void)archiveAllSessionsForAddress:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction;
- (void)archiveAllSessionsForAccountId:(NSString *)accountId transaction:(SDSAnyWriteTransaction *)transaction;

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
