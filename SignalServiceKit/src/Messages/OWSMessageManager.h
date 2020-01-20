//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SSKProtoEnvelope;

@interface OWSMessageManager : OWSMessageHandler

// processEnvelope: can be called from any thread.
- (void)processEnvelope:(SSKProtoEnvelope *)envelope
          plaintextData:(NSData *_Nullable)plaintextData
        wasReceivedByUD:(BOOL)wasReceivedByUD
            transaction:(SDSAnyWriteTransaction *)transaction
                success:(void (^)(void))success
                failure:(void (^)(void))failure;

// This should be invoked by the main app when the app is ready.
- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
