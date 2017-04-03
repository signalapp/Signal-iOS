//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSPrivacyPreferences.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const TSPrivacyPreferencesSingletonKey = @"TSPrivacyPreferences";

@implementation TSPrivacyPreferences

+ (instancetype)sharedInstance
{
    static TSPrivacyPreferences *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self fetchObjectWithUniqueID:TSPrivacyPreferencesSingletonKey];
        if (!sharedInstance) {
            sharedInstance = [[self alloc] initDefault];
        }
    });

    return sharedInstance;
}

- (instancetype)initDefault
{
    return [self initWithShouldBlockOnIdentityChange:YES];
}

- (instancetype)initWithShouldBlockOnIdentityChange:(BOOL)shouldBlockOnIdentityChange
{
    self = [super initWithUniqueId:TSPrivacyPreferencesSingletonKey];
    if (!self) {
        return self;
    }

    _shouldBlockOnIdentityChange = shouldBlockOnIdentityChange;

    OWSSingletonAssert();

    return self;
}

@end

NS_ASSUME_NONNULL_END
