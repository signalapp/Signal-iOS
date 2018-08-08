//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAsserts.h"

NS_ASSUME_NONNULL_BEGIN

void SwiftAssertIsOnMainThread(NSString *functionName)
{
    if (![NSThread isMainThread]) {
        OWSCFailNoProdLog(@"%@ not on main thread", functionName);
    }
}

NS_ASSUME_NONNULL_END
