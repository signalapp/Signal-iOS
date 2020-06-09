//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSDispatch : NSObject

/**
 * Attachment downloading
 */
+ (dispatch_queue_t)attachmentsQueue;

@end

NS_ASSUME_NONNULL_END
