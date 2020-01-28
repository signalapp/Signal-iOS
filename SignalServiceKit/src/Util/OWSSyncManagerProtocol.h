//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class SignalAccount;
@class YapDatabaseReadTransaction;

@protocol OWSSyncManagerProtocol <NSObject>

- (void)sendConfigurationSyncMessage;

- (AnyPromise *)syncLocalContact __attribute__((warn_unused_result));

- (AnyPromise *)syncContact:(NSString *)hexEncodedPubKey transaction:(YapDatabaseReadTransaction *)transaction;

- (AnyPromise *)syncAllContacts __attribute__((warn_unused_result));

- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts __attribute__((warn_unused_result));

@end

NS_ASSUME_NONNULL_END
