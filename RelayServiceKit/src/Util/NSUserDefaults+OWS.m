//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSUserDefaults+OWS.h"
#import "AppContext.h"
#import "TSConstants.h"
#import "CCSMStorage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSUserDefaults (OWS)

+ (NSUserDefaults *)appUserDefaults
{
    NSString *suiteName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"AppGroupPath"];
//    NSString *suiteName = CCSMEnvironment.sharedInstance.appGroupIdString;
    return [[NSUserDefaults alloc] initWithSuiteName:suiteName];
}

+ (void)migrateToSharedUserDefaults
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSUserDefaults *appUserDefaults = self.appUserDefaults;

    NSDictionary<NSString *, id> *dictionary = [NSUserDefaults standardUserDefaults].dictionaryRepresentation;
    for (NSString *key in dictionary) {
        id value = dictionary[key];
        OWSAssert(value);
        [appUserDefaults setObject:value forKey:key];
    }
}

+ (void)removeAll
{
    [NSUserDefaults.standardUserDefaults removeAll];
    [self.appUserDefaults removeAll];
}

- (void)removeAll
{
    OWSAssert(CurrentAppContext().isMainApp);

    NSDictionary<NSString *, id> *dictionary = self.dictionaryRepresentation;
    for (NSString *key in dictionary) {
        [self removeObjectForKey:key];
    }
    [self synchronize];
}

@end

NS_ASSUME_NONNULL_END
