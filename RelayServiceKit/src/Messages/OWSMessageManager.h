//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class SSKEnvelope;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

@interface OWSMessageManager : OWSMessageHandler

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

// processEnvelope: can be called from any thread.
- (void)processEnvelope:(SSKEnvelope *)envelope
          plaintextData:(NSData *_Nullable)plaintextData
            transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
