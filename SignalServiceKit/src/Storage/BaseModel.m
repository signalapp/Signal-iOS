//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "BaseModel.h"

NS_ASSUME_NONNULL_BEGIN

@implementation BaseModel

+ (BOOL)shouldBeIndexedForFTS
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
