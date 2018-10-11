//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"

BOOL IsUsingProductionService()
{
#ifdef USING_PRODUCTION_SERVICE
    return YES;
#else
    return NO;
#endif
}
