//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSRegisterForPushRequest : TSRequest

- (id)initWithPushIdentifier:(NSString *)identifier voipIdentifier:(NSString *)voipId;

@end

NS_ASSUME_NONNULL_END
