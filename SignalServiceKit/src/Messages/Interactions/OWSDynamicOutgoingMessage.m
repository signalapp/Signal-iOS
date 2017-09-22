//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDynamicOutgoingMessage.h"
#import "NSDate+OWS.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDynamicOutgoingMessage ()

@property (nonatomic, readonly) DynamicOutgoingMessageBlock block;

@end

#pragma mark -

@implementation OWSDynamicOutgoingMessage

- (instancetype)initWithPlainTextDataBlock:(DynamicOutgoingMessageBlock)block thread:(nullable TSThread *)thread
{
    return [self initWithPlainTextDataBlock:block timestamp:[NSDate ows_millisecondTimeStamp] thread:thread];
}

- (instancetype)initWithPlainTextDataBlock:(DynamicOutgoingMessageBlock)block
                                 timestamp:(uint64_t)timestamp
                                    thread:(nullable TSThread *)thread
{
    self = [super initWithTimestamp:timestamp inThread:thread];

    if (self) {
        _block = block;
    }

    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // override superclass with no-op.
    //
    // There's no need to save this message, since it's not displayed to the user.
}

- (NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    NSData *plainTextData = self.block(recipient);
    OWSAssert(plainTextData);
    return plainTextData;
}

@end

NS_ASSUME_NONNULL_END
