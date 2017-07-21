//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@class YapDatabase;

@interface OWSReadReceipt : TSYapDatabaseObject

@property (nonatomic, readonly) NSString *senderId;
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly, getter=isValid) BOOL valid;
@property (nonatomic, readonly) NSArray<NSString *> *validationErrorMessages;

- (instancetype)initWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp;

+ (nullable instancetype)firstWithSenderId:(NSString *)senderId timestamp:(uint64_t)timestamp;
+ (void)asyncRegisterIndexOnSenderIdAndTimestampWithDatabase:(YapDatabase *)database;

@end

NS_ASSUME_NONNULL_END
