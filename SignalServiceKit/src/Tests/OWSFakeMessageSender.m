//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeMessageSender.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation OWSFakeMessageSender

- (void)enqueueMessage:(TSOutgoingMessage *)message
               success:(void (^)(void))successHandler
               failure:(void (^)(NSError *error))failureHandler
{
    if (self.enqueueMessageBlock) {
        self.enqueueMessageBlock();
    }
    successHandler();
}

- (void)enqueueAttachment:(DataSource *)dataSource
              contentType:(NSString *)contentType
           sourceFilename:(nullable NSString *)sourceFilename
                inMessage:(TSOutgoingMessage *)outgoingMessage
                  success:(void (^)(void))successHandler
                  failure:(void (^)(NSError *error))failureHandler
{
    if (self.enqueueAttachmentBlock) {
        self.enqueueAttachmentBlock();
    }
    successHandler();
}

- (void)enqueueTemporaryAttachment:(DataSource *)dataSource
                       contentType:(NSString *)contentType
                         inMessage:(TSOutgoingMessage *)outgoingMessage
                           success:(void (^)(void))successHandler
                           failure:(void (^)(NSError *error))failureHandler
{
    if (self.enqueueTemporaryAttachmentBlock) {
        self.enqueueTemporaryAttachmentBlock();
    }
    successHandler();
}


@end

#endif

NS_ASSUME_NONNULL_END
