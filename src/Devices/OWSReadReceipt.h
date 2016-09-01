//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceipt : NSObject

@property (nonatomic, readonly) NSString *senderId;
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly, getter=isValid) BOOL valid;
@property (nonatomic, readonly) NSArray<NSString *> *validationErrorMessages;

- (instancetype)initWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp;

@end

NS_ASSUME_NONNULL_END