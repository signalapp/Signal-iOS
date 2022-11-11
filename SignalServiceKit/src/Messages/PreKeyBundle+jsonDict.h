//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/PreKeyBundle.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreKeyBundle (jsonDict)

+ (nullable PreKeyBundle *)preKeyBundleFromDictionary:(NSDictionary *)dictionary forDeviceNumber:(NSNumber *)number;

@end

NS_ASSUME_NONNULL_END
