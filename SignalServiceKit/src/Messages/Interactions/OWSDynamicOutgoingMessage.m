//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDynamicOutgoingMessage.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDynamicOutgoingMessage ()

@property (nonatomic, readonly) DynamicOutgoingMessageBlock block;

@end

#pragma mark -

@implementation OWSDynamicOutgoingMessage

- (instancetype)initWithBlock:(DynamicOutgoingMessageBlock)block inThread:(nullable TSThread *)thread
{
    self = [super initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread];

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
