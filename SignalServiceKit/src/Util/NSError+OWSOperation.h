//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSError (OWSOperation)

@property (nonatomic) BOOL isRetryable;
@property (nonatomic) BOOL isFatal;
@property (nonatomic) BOOL shouldBeIgnoredForGroups;

@end

NS_ASSUME_NONNULL_END
