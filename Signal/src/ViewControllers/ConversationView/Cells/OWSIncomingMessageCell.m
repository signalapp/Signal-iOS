//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSIncomingMessageCell.h"
#import "ConversationViewItem.h"
#import <SignalServiceKit/TSIncomingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSIncomingMessageCell

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (BOOL)isIncoming
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
