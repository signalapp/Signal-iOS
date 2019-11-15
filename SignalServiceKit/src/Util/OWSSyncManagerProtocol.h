//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class SDSAnyWriteTransaction;
@class SSKProtoSyncMessageConfiguration;
@class SSKProtoSyncMessageContacts;
@class SSKProtoSyncMessageFetchLatest;
@class SSKProtoSyncMessageGroups;
@class SignalAccount;

@protocol OWSSyncManagerProtocol <NSObject>

- (void)sendConfigurationSyncMessage;

- (AnyPromise *)objc_sendAllSyncRequestMessages __attribute__((warn_unused_result));
- (AnyPromise *)objc_sendAllSyncRequestMessagesWithTimeout:(NSTimeInterval)timeout __attribute__((warn_unused_result))
                                                           NS_SWIFT_NAME(objc_sendAllSyncRequestMessages(timeout:));

- (AnyPromise *)syncLocalContact __attribute__((warn_unused_result));

- (AnyPromise *)syncAllContacts __attribute__((warn_unused_result));

- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts __attribute__((warn_unused_result));

- (void)syncGroupsWithTransaction:(SDSAnyWriteTransaction *)transaction;

- (void)processIncomingConfigurationSyncMessage:(SSKProtoSyncMessageConfiguration *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction;
- (void)processIncomingContactsSyncMessage:(SSKProtoSyncMessageContacts *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction;
- (void)processIncomingGroupsSyncMessage:(SSKProtoSyncMessageGroups *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction;

- (void)sendFetchLatestProfileSyncMessage;
- (void)sendFetchLatestStorageManifestSyncMessage;
- (void)sendKeysSyncMessage;

- (void)processIncomingFetchLatestSyncMessage:(SSKProtoSyncMessageFetchLatest *)syncMessage
                                  transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
