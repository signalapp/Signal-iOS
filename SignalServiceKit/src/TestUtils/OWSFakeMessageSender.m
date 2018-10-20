//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeMessageSender.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation OWSFakeMessageSender

- (void)sendMessage:(TSOutgoingMessage *)message
            success:(void (^)(void))successHandler
            failure:(void (^)(NSError *error))failureHandler
{
    if (self.sendMessageWasCalledBlock) {
        self.sendMessageWasCalledBlock(message);
    }

    if (self.stubbedFailingError) {
        failureHandler(self.stubbedFailingError);
    } else {
        successHandler();
    }
}

- (void)sendAttachment:(DataSource *)dataSource
           contentType:(NSString *)contentType
        sourceFilename:(nullable NSString *)sourceFilename
             inMessage:(TSOutgoingMessage *)outgoingMessage
               success:(void (^)(void))successHandler
               failure:(void (^)(NSError *error))failureHandler
{
    if (self.sendAttachmentWasCalledBlock) {
        self.sendAttachmentWasCalledBlock(outgoingMessage);
    }

    if (self.stubbedFailingError) {
        failureHandler(self.stubbedFailingError);
    } else {
        successHandler();
    }
}

- (void)sendTemporaryAttachment:(DataSource *)dataSource
                    contentType:(NSString *)contentType
                      inMessage:(TSOutgoingMessage *)outgoingMessage
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    if (self.sendTemporaryAttachmentWasCalledBlock) {
        self.sendTemporaryAttachmentWasCalledBlock(outgoingMessage);
    }

    if (self.stubbedFailingError) {
        failureHandler(self.stubbedFailingError);
    } else {
        successHandler();
    }
}


@end

#endif

NS_ASSUME_NONNULL_END
