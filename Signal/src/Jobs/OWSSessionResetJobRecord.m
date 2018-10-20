//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSessionResetJobRecord.h"
#import <SignalServiceKit/TSContactThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSSessionResetJobRecord

- (instancetype)initWithContactThread:(TSContactThread *)contactThread label:(NSString *)label
{
    self = [super initWithLabel:label];
    if (!self) {
        return self;
    }

    _contactThreadId = contactThread.uniqueId;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

@end

NS_ASSUME_NONNULL_END
