//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSChunkedOutputStream.h"
#import <ProtocolBuffers/CodedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSChunkedOutputStream

+ (instancetype)streamWithOutputStream:(NSOutputStream *)output
{
    return [[self alloc] initWithOutputStream:output];
}

- (instancetype)initWithOutputStream:(NSOutputStream *)outputStream
{
    self = [super init];
    if (!self) {
        return self;
    }

    _delegateStream = [PBCodedOutputStream streamWithOutputStream:outputStream];

    return self;
}

- (void)flush
{
    [self.delegateStream flush];
}


@end

NS_ASSUME_NONNULL_END
