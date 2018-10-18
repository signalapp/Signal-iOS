//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class SignalAccount;

@protocol OWSSyncManagerProtocol <NSObject>

- (void)sendConfigurationSyncMessage;

- (AnyPromise *)syncLocalContact;

- (AnyPromise *)syncAllContacts;

- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts;

@end

NS_ASSUME_NONNULL_END
