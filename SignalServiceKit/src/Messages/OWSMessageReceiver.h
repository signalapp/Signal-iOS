//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class OWSStorage;

// This class is used to write incoming (encrypted, unprocessed)
// messages to a durable queue and then decrypt them in the order
// in which they were received.  Successfully decrypted messages
// are forwarded to OWSBatchMessageProcessor.
@interface OWSMessageReceiver : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage;

- (void)handleReceivedEnvelopeData:(NSData *)envelopeData;

@end

NS_ASSUME_NONNULL_END
