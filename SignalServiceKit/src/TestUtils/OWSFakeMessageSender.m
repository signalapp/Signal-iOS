//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeMessageSender.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@implementation OWSFakeMessageSender

- (void)sendMessage:(OutgoingMessagePreparer *)outgoingMessagePreparer
            success:(void (^)(void))successHandler
            failure:(void (^)(NSError *error))failureHandler
{
    OWSAssertDebug([outgoingMessagePreparer isKindOfClass:[OutgoingMessagePreparer class]]);

    if (self.stubbedFailingError) {
        failureHandler(self.stubbedFailingError);
    } else {
        successHandler();
    }
    if (self.sendMessageWasCalledBlock) {
        self.sendMessageWasCalledBlock(outgoingMessagePreparer.message);
    }
}

- (void)sendAttachment:(id<DataSource>)dataSource
           contentType:(NSString *)contentType
        sourceFilename:(nullable NSString *)sourceFilename
             inMessage:(TSOutgoingMessage *)outgoingMessage
               success:(void (^)(void))successHandler
               failure:(void (^)(NSError *error))failureHandler
{
    if (self.stubbedFailingError) {
        failureHandler(self.stubbedFailingError);
    } else {
        successHandler();
    }
    if (self.sendAttachmentWasCalledBlock) {
        self.sendAttachmentWasCalledBlock(outgoingMessage);
    }
}

- (void)sendTemporaryAttachment:(id<DataSource>)dataSource
                    contentType:(NSString *)contentType
                      inMessage:(TSOutgoingMessage *)outgoingMessage
                        success:(void (^)(void))successHandler
                        failure:(void (^)(NSError *error))failureHandler
{
    if (self.stubbedFailingError) {
        failureHandler(self.stubbedFailingError);
    } else {
        successHandler();
    }
    if (self.sendTemporaryAttachmentWasCalledBlock) {
        self.sendTemporaryAttachmentWasCalledBlock(outgoingMessage);
    }
}


@end

#endif

NS_ASSUME_NONNULL_END
