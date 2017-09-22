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

- (instancetype)initWithBlock:(DynamicOutgoingMessageBlock)block thread:(nullable TSThread *)thread
{
    return [self initWithBlock:block timestamp:[NSDate ows_millisecondTimeStamp] thread:thread];
}

- (instancetype)initWithBlock:(DynamicOutgoingMessageBlock)block
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

//- (OWSSignalServiceProtosDataMessageBuilder *)dataMessageBuilder
//{
//    OWSSignalServiceProtosDataMessageBuilder *builder = [super dataMessageBuilder];
//    [builder setFlags:OWSSignalServiceProtosDataMessageFlagsEndSession];
//
//    return builder;
//}

- (NSData *)buildPlainTextData:(SignalRecipient *)recipient
{
    NSData *plainTextData = self.block(recipient);
    OWSAssert(plainTextData);
    return plainTextData;
    //    OWSSignalServiceProtosContentBuilder *contentBuilder = [OWSSignalServiceProtosContentBuilder new];
    //    contentBuilder.dataMessage = [self buildDataMessage:recipient.recipientId];
    //    return [[contentBuilder build] data];
}
@end

NS_ASSUME_NONNULL_END
