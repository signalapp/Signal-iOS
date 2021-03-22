//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/PreKeyBundle.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreKeyBundle (jsonDict)

+ (nullable PreKeyBundle *)preKeyBundleFromDictionary:(NSDictionary *)dictionary forDeviceNumber:(NSNumber *)number;

@end

NS_ASSUME_NONNULL_END
