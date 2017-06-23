//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalsViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class OWSMessageSender;
@class OWSIdentityManager;

@interface OWSContactsSyncing : NSObject

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                        identityManager:(OWSIdentityManager *)identityManager
                          messageSender:(OWSMessageSender *)messageSender;

@end

NS_ASSUME_NONNULL_END
