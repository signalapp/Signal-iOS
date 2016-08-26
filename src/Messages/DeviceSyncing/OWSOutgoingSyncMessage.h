//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Abstract base class used for the family of sync messages which take care
 * of keeping your multiple registered devices consistent. E.g. sharing contacts, sharing groups,
 * notifiying your devices of sent messages, and "read" receipts.
 */
@interface OWSOutgoingSyncMessage : TSOutgoingMessage

@end

NS_ASSUME_NONNULL_END
