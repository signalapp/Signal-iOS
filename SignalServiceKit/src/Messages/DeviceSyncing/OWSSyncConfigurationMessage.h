//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncConfigurationMessage : OWSOutgoingSyncMessage

- (instancetype)initWithReadReceiptsEnabled:(BOOL)readReceiptsEnabled;

@end

NS_ASSUME_NONNULL_END
