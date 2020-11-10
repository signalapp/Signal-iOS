//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AnyPromise;
@class SignalAccount;
@class YapDatabaseReadTransaction;
@class TSGroupThread;

@protocol OWSSyncManagerProtocol <NSObject>

- (void)sendConfigurationSyncMessage;

- (AnyPromise *)syncLocalContact __attribute__((warn_unused_result));

- (AnyPromise *)syncContact:(NSString *)hexEncodedPubKey transaction:(YapDatabaseReadTransaction *)transaction;

- (AnyPromise *)syncAllContacts __attribute__((warn_unused_result));

- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts __attribute__((warn_unused_result));

- (AnyPromise *)syncAllGroups __attribute__((warn_unused_result));

- (AnyPromise *)syncGroupForThread:(TSGroupThread *)thread;

- (AnyPromise *)syncAllOpenGroups __attribute__((warn_unused_result));

@end

NS_ASSUME_NONNULL_END
