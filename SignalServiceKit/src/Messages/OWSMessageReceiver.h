//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;
@class TSStorageManager;

// This class is used to write incoming (encrypted, unprocessed)
// messages to a durable queue and then decrypt them in the order
// in which they were received.  Successfully decrypted messages
// are forwarded to OWSBatchMessageProcessor.
@interface OWSMessageReceiver : NSObject

+ (instancetype)sharedInstance;
+ (void)syncRegisterDatabaseExtension:(TSStorageManager *)storageManager;

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope;
- (void)handleAnyUnprocessedEnvelopesAsync;

@end

NS_ASSUME_NONNULL_END
