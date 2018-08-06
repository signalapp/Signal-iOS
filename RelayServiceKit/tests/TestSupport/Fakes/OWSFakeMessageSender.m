//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeMessageSender.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFakeMessageSender

- (instancetype)initWithExpectation:(XCTestExpectation *)expectation
{
    self = [self init];
    if (!self) {
        return self;
    }

    _expectation = expectation;

    return self;
}

- (void)sendTemporaryAttachmentData:(NSData *)attachmentData
                        contentType:(NSString *)contentType
                          inMessage:(TSOutgoingMessage *)outgoingMessage
                            success:(void (^)())successHandler
                            failure:(void (^)(NSError *error))failureHandler
{

    NSLog(@"Faking sendTemporyAttachmentData.");
    [self.expectation fulfill];
    successHandler();
}

@end

NS_ASSUME_NONNULL_END
