//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;
@class YapDatabase;

// This class is used to write incoming (decrypted, unprocessed)
// messages to a durable queue and then process them in batches,
// in the order in which they were received.
@interface OWSBatchMessageProcessor : NSObject

+ (instancetype)sharedInstance;
+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database;

- (void)enqueueEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData;
- (void)handleAnyUnprocessedEnvelopesAsync;

@end

NS_ASSUME_NONNULL_END
