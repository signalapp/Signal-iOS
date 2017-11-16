//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFileSystem.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFileSystem

+ (void)protectFolderAtPath:(NSString *)path
{
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }

    NSError *error;
    NSDictionary *fileProtection = @{ NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication };
    [[NSFileManager defaultManager] setAttributes:fileProtection ofItemAtPath:path error:&error];

    NSDictionary *resourcesAttrs = @{ NSURLIsExcludedFromBackupKey : @YES };

    NSURL *ressourceURL = [NSURL fileURLWithPath:path];
    BOOL success = [ressourceURL setResourceValues:resourcesAttrs error:&error];

    if (error || !success) {
        OWSProdCritical([OWSAnalyticsEvents storageErrorFileProtection]);
    }
}

@end

NS_ASSUME_NONNULL_END
