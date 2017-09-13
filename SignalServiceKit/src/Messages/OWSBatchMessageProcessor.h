//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;
@class YapDatabase;

@interface OWSBatchMessageProcessor : NSObject

+ (instancetype)sharedInstance;
+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database;

- (void)enqueueEnvelopeData:(NSData *)envelopeData plaintextData:(NSData *_Nullable)plaintextData;
- (void)handleAnyUnprocessedEnvelopesAsync;

@end

NS_ASSUME_NONNULL_END
