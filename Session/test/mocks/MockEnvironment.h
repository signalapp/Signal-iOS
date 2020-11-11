//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"

NS_ASSUME_NONNULL_BEGIN

@interface MockEnvironment : Environment

+ (MockEnvironment *)activate;

- (instancetype)init;

@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) OWSPreferences *preferences;
@property (nonatomic) OWSSounds *sounds;
@property (nonatomic) OWSWindowManager *windowManager;

@end

NS_ASSUME_NONNULL_END
