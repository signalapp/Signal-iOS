//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SelectThreadViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class SignalAttachment;

@interface SendExternalFileViewController : SelectThreadViewController

@property (nonatomic) SignalAttachment *attachment;

@end

NS_ASSUME_NONNULL_END
