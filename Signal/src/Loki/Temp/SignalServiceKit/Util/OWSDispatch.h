//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSDispatch : NSObject

/**
 * Attachment downloading
 */
+ (dispatch_queue_t)attachmentsQueue;

/**
 * Serial message sending queue
 */
+ (dispatch_queue_t)sendingQueue;

@end

NS_ASSUME_NONNULL_END
