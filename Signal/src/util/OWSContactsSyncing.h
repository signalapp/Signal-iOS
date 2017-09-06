//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "HomeViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class OWSMessageSender;
@class OWSIdentityManager;
@class OWSProfileManager;

@interface OWSContactsSyncing : NSObject

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                        identityManager:(OWSIdentityManager *)identityManager
                          messageSender:(OWSMessageSender *)messageSender
                         profileManager:(OWSProfileManager *)profileManager;

@end

NS_ASSUME_NONNULL_END
