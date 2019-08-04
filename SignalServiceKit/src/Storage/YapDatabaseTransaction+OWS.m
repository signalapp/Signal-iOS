//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "YapDatabaseTransaction+OWS.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation YapDatabaseReadTransaction (OWS)

#pragma mark - Extensions

- (nullable id)safe_extension:(NSString *)extensionName clazz:(Class)clazz
{
    id _Nullable result = [self extension:extensionName];

    if (![result isKindOfClass:clazz]) {
        [OWSPrimaryStorage incrementVersionOfDatabaseExtension:extensionName];

        if (SSKFeatureFlags.strictYDBExtensions) {
            OWSFail(@"Couldn't load database extension: %@.", extensionName);
        } else {
            LogStackTrace();
            OWSFailDebug(@"Couldn't load database extension: %@.", extensionName);
        }
        return nil;
    }
    return result;
}

- (nullable YapDatabaseViewTransaction *)safeViewTransaction:(NSString *)extensionName
{
    return [self safe_extension:extensionName clazz:[YapDatabaseViewTransaction class]];
}

- (nullable YapDatabaseAutoViewTransaction *)safeAutoViewTransaction:(NSString *)extensionName
{
    return [self safe_extension:extensionName clazz:[YapDatabaseAutoViewTransaction class]];
}

- (nullable YapDatabaseSecondaryIndexTransaction *)safeSecondaryIndexTransaction:(NSString *)extensionName
{
    return [self safe_extension:extensionName clazz:[YapDatabaseSecondaryIndexTransaction class]];
}

- (nullable YapDatabaseFullTextSearchTransaction *)safeFullTextSearchTransaction:(NSString *)extensionName
{
    return [self safe_extension:extensionName clazz:[YapDatabaseFullTextSearchTransaction class]];
}

@end

NS_ASSUME_NONNULL_END
