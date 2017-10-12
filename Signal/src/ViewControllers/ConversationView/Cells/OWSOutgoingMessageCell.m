//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingMessageCell.h"
#import "ConversationViewItem.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSOutgoingMessageCell

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (BOOL)isIncoming
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
