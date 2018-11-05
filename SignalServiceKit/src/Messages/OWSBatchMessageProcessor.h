//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class OWSStorage;
@class SSKProtoEnvelope;
@class YapDatabaseReadWriteTransaction;

// This class is used to write incoming (decrypted, unprocessed)
// messages to a durable queue and then process them in batches,
// in the order in which they were received.
@interface OWSBatchMessageProcessor : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage;

- (void)enqueueEnvelopeData:(NSData *)envelopeData
              plaintextData:(NSData *_Nullable)plaintextData
                transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
