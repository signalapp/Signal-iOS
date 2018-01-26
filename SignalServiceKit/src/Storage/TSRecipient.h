//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// Some lingering TSRecipient records in the wild causing crashes.
// This is a stop gap until a proper cleanup happens.
@interface TSRecipient : NSObject <NSCoding>

@end

NS_ASSUME_NONNULL_END
