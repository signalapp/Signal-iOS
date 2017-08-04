//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSProfileAvatarUploadFormRequest.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSProfileAvatarUploadFormRequest

- (nullable instancetype)init
{
    self = [super initWithURL:[NSURL URLWithString:textSecureProfileAvatarFormAPI]];

    self.HTTPMethod = @"GET";

    return self;
}

@end

NS_ASSUME_NONNULL_END
