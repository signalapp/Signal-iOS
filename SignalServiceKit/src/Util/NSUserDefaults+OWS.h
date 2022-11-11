//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (OWS)

+ (NSUserDefaults *)appUserDefaults;

+ (void)removeAll;

@end

NS_ASSUME_NONNULL_END
