//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (OWS)

+ (NSUserDefaults *)appUserDefaults;

+ (void)removeAll;

@end

NS_ASSUME_NONNULL_END
