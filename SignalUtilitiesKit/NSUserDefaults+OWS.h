//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (OWS)

+ (NSUserDefaults *)appUserDefaults;

+ (void)migrateToSharedUserDefaults;

+ (void)removeAll;

@end

NS_ASSUME_NONNULL_END
