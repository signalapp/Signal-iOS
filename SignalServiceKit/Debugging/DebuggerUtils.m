//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebuggerUtils.h"

#ifdef DEBUG

#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

// Inspired by https://developer.apple.com/library/archive/qa/qa1361/_index.html.
BOOL IsDebuggerAttached(void)
{
    int name[4] = {
        CTL_KERN,
        KERN_PROC,
        KERN_PROC_PID, // Requesting info about a specific process
        getpid(), // And that process is this one.
    };

    struct kinfo_proc old = { 0 };
    size_t oldlen = sizeof(old);
    const int rc = sysctl(name, sizeof(name) / sizeof(*name), &old, &oldlen, NULL /* newp */, 0 /* newlen */);

    if (rc != 0) {
        // There's no good reason for this to happen.
        return NO;
    }

    return (old.kp_proc.p_flag & P_TRACED) != 0;
}

void TrapDebugger(void)
{
    // __builtin_debugtrap doesn't respect lldb's breakpoints enabled setting.
    // To temporarily disable this "breakpoint" set enabled to NO.
    static BOOL enabled = YES;
    if (!enabled) {
        return;
    }

    __builtin_debugtrap();
}

#endif // DEBUG
