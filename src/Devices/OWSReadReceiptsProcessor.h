//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosSyncMessageRead;

@interface OWSReadReceiptsProcessor : NSObject

- (instancetype)initWithReadReceiptProtos:(NSArray<OWSSignalServiceProtosSyncMessageRead *> *)readReceiptProtos
    NS_DESIGNATED_INITIALIZER;
- (void)process;

@end

NS_ASSUME_NONNULL_END