//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSPhotoAdapter.h"
#import "TSAttachmentStream.h"
#import "JSQMediaItem+OWS.h"
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>

@interface TSPhotoAdapter ()

@property (strong, nonatomic) UIImageView *cachedImageView;
@end

@implementation TSPhotoAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment {
    self = [super initWithImage:attachment.image];

    if (!self) {
        return self;
    }

    _cachedImageView = nil;
    _attachment = attachment;
    _attachmentId = attachment.uniqueId;

    return self;
}

- (void)dealloc {
    self.image       = nil;
    _cachedImageView = nil;
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing {
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView {
    if (self.image == nil) {
        return nil;
    }

    if (self.cachedImageView == nil) {
        CGSize size             = [self mediaViewDisplaySize];
        UIImageView *imageView  = [[UIImageView alloc] initWithImage:self.image];
        imageView.frame         = CGRectMake(0.0f, 0.0f, size.width, size.height);
        imageView.contentMode   = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        imageView.layer.minificationFilter = kCAFilterTrilinear;
        imageView.layer.magnificationFilter = kCAFilterTrilinear;
        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView
                                                                    isOutgoing:self.appliesMediaViewMaskAsOutgoing];
        self.cachedImageView = imageView;
    }

    return self.cachedImageView;
}

- (CGSize)mediaViewDisplaySize {
    return [self ows_adjustBubbleSize:[super mediaViewDisplaySize] forImage:self.image];
}

- (BOOL)isImage {
    return YES;
}


- (BOOL)isAudio {
    return NO;
}


- (BOOL)isVideo {
    return NO;
}

#pragma mark - OWSMessageEditing Protocol

- (BOOL)canPerformEditingAction:(SEL)action
{
    return (action == @selector(copy:) || action == NSSelectorFromString(@"save:"));
}

- (void)performEditingAction:(SEL)action
{
    NSString *actionString = NSStringFromSelector(action);
    if (!self.image) {
        DDLogWarn(@"Refusing to perform '%@' action with nil image for %@: attachmentId=%@. (corrupted attachment?)",
            actionString,
            self.class,
            self.attachmentId);
        return;
    }

    if (action == @selector(copy:)) {
        UIPasteboard.generalPasteboard.image = self.image;
        return;
    } else if (action == NSSelectorFromString(@"save:")) {
        UIImageWriteToSavedPhotosAlbum(self.image, nil, nil, nil);
        return;
    }

    // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
    DDLogError(@"'%@' action unsupported for %@: attachmentId=%@", actionString, self.class, self.attachmentId);
}

@end
