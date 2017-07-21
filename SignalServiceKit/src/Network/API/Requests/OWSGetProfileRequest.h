//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSGetProfileRequest : TSRequest

- (instancetype)initWithRecipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
