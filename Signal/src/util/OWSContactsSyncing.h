//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalsViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class OWSMessageSender;

@interface OWSContactsSyncing : NSObject

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                          messageSender:(OWSMessageSender *)messageSender;

@end

NS_ASSUME_NONNULL_END
