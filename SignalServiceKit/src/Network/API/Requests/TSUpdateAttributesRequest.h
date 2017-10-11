//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSUpdateAttributesRequest : TSRequest

- (instancetype)initWithManualMessageFetching:(BOOL)isEnabled;

@end
