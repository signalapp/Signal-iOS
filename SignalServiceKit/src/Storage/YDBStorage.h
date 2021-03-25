//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface YDBStorage : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)deleteYDBStorage NS_SWIFT_NAME(deleteYDBStorage());

+ (BOOL)hasAnyYdbFile;

@end

NS_ASSUME_NONNULL_END
