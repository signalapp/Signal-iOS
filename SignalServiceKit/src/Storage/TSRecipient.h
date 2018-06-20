//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

// Some lingering TSRecipient records in the wild causing crashes.
// This is a stop gap until a proper cleanup happens.
@interface TSRecipient : TSYapDatabaseObject

@end

NS_ASSUME_NONNULL_END
