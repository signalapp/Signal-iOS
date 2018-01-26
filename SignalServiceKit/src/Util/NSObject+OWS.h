//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (OWS)

#pragma mark - Logging

@property (nonatomic, readonly) NSString *logTag;

+ (NSString *)logTag;

@end

NS_ASSUME_NONNULL_END
