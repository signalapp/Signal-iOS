//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalAccount.h"
#import <SignalServiceKit/SignalRecipient.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalAccount

- (NSString *)recipientId
{
    OWSAssert(self.signalRecipient);

    return self.signalRecipient.uniqueId;
}

@end

NS_ASSUME_NONNULL_END
