//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AppDelegate.h"

int main(int argc, char *argv[])
{
    NSString *appDelegateName;

    @autoreleasepool {
        // Any setup work pre-UIApplicationMain() should be placed
        // inside this autoreleasepool.
        appDelegateName = NSStringFromClass(AppDelegate.class);
    }

    // UIApplicationMain is intentionally called outside of the above
    // autoreleasepool. The function never returns, so its parent
    // autoreleasepool will never be drained.
    return UIApplicationMain(argc, argv, nil, appDelegateName);
}
