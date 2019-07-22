//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class SDSAnyWriteTransaction;
@class SignalAccount;

@protocol OWSSyncManagerProtocol <NSObject>

- (void)sendConfigurationSyncMessage;

- (AnyPromise *)syncLocalContact __attribute__((warn_unused_result));

- (AnyPromise *)syncAllContacts __attribute__((warn_unused_result));

- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts __attribute__((warn_unused_result));

- (void)syncGroupsWithTransaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
