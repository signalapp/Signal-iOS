//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSCallMessageHandler.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeCallMessageHandler : NSObject <OWSCallMessageHandler>

@end

#endif

NS_ASSUME_NONNULL_END
