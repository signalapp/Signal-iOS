//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMath.h"

NS_ASSUME_NONNULL_BEGIN

void SetRandFunctionSeed(void)
{
    // Set the seed the generator for rand().
    //
    // We should always use arc4random() instead of rand(), but we
    // still want to ensure that any third-party code that uses rand()
    // gets random values.
    srand((unsigned int)time(NULL));
}

NS_ASSUME_NONNULL_END
