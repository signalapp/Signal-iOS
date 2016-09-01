//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceipt.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSReadReceipt

- (instancetype)initWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp;
{
    self = [super init];
    if (!self) {
        return self;
    }

    NSMutableArray<NSString *> *validationErrorMessage = [NSMutableArray new];
    if (!senderId) {
        [validationErrorMessage addObject:@"Must specify sender id"];
    }
    _senderId = senderId;

    if (!timestamp) {
        [validationErrorMessage addObject:@"Must specify timestamp"];
    }
    _timestamp = timestamp;

    _valid = validationErrorMessage.count == 0;
    _validationErrorMessages = [validationErrorMessage copy];

    return self;
}

@end

NS_ASSUME_NONNULL_END
