//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

// This entity is used to display upload progress for outgoing
// attachments in conversation view cells.
//
// During attachment uploads we want to:
//
// * Dim the media view using a mask layer.
// * Show and update a progress bar.
// * Disable any media view controls using a callback.
@interface AttachmentUploadView : UIView

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment;

@end

NS_ASSUME_NONNULL_END
