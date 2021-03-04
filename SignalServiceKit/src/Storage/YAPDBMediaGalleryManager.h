//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;

@interface YAPDBMediaGalleryManager : NSObject

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
