//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalsViewController.h"

@class OWSContactsManager;
@class OWSMessageSender;

@interface OWSContactsSyncing : NSObject

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                          messageSender:(OWSMessageSender *)messageSender;

@end
