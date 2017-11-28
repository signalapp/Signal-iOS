//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFileSystem.h"
#import "TSConstants.h"

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

+ (NSString *)appDocumentDirectoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL =
        [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [documentDirectoryURL path];
}

+ (NSString *)appSharedDataDirectoryPath
{
    NSURL *groupContainerDirectoryURL =
        [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SignalApplicationGroup];
    return [groupContainerDirectoryURL path];
}

+ (void)moveAppFilePath:(NSString *)oldFilePath
     sharedDataFilePath:(NSString *)newFilePath
          exceptionName:(NSString *)exceptionName
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:oldFilePath]) {
        return;
    }
    if ([fileManager fileExistsAtPath:newFilePath]) {
        OWSFail(
            @"%@ Can't move file from %@ to %@; destination already exists.", self.logTag, oldFilePath, newFilePath);
        return;
    }
    
    NSDate *startDate = [NSDate new];
    
    NSError *_Nullable error;
    BOOL success = [fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:&error];
    if (!success || error) {
        NSString *errorDescription =
            [NSString stringWithFormat:@"%@ Could not move file or directory from %@ to %@, error: %@",
                      self.logTag,
                      oldFilePath,
                      newFilePath,
                      error];
        OWSFail(@"%@", errorDescription);
        [NSException raise:exceptionName format:@"%@", errorDescription];
    }
    
    DDLogInfo(@"%@ Moving file or directory from %@ to %@ in: %f",
              self.logTag,
              oldFilePath,
              newFilePath,
              fabs([startDate timeIntervalSinceNow]));
}

@end

NS_ASSUME_NONNULL_END
