//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSPhotoAdapter.h"
#import "AttachmentUploadView.h"
#import "JSQMediaItem+OWS.h"
#import "TSAttachmentStream.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/MimeTypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSPhotoAdapter ()

@property (nonatomic, nullable) UIImageView *cachedImageView;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL incoming;
@property (nonatomic) CGSize imageSize;

// See comments on OWSMessageMediaAdapter.
@property (nonatomic, nullable, weak) id lastPresentingCell;

@end

#pragma mark -

@implementation TSPhotoAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming
{
    self = [super init];

    if (!self) {
        return self;
    }

    _cachedImageView = nil;
    _attachment = attachment;
    _attachmentId = attachment.uniqueId;
    _incoming = incoming;
    _imageSize = [attachment imageSizeWithoutTransaction];

    return self;
}

- (void)clearAllViews
{
    OWSAssert([NSThread isMainThread]);

    [_cachedImageView removeFromSuperview];
    _cachedImageView = nil;
    _attachmentUploadView = nil;
}

- (void)clearCachedMediaViews
{
    [super clearCachedMediaViews];
    [self clearAllViews];
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing {
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    [self clearAllViews];
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView {
    OWSAssert([NSThread isMainThread]);

    if (self.cachedImageView == nil) {
        UIImage *image = self.attachment.image;
        if (!image) {
            DDLogError(@"%@ Could not load image: %@", [self tag], [self.attachment mediaURL]);
            OWSAssert(0);
            return nil;
        }
        CGSize size             = [self mediaViewDisplaySize];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        imageView.contentMode   = UIViewContentModeScaleAspectFill;
        imageView.frame         = CGRectMake(0.0f, 0.0f, size.width, size.height);
        imageView.clipsToBounds = YES;
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        imageView.layer.minificationFilter = kCAFilterTrilinear;
        imageView.layer.magnificationFilter = kCAFilterTrilinear;
        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView
                                                                    isOutgoing:self.appliesMediaViewMaskAsOutgoing];
        self.cachedImageView = imageView;

        if (!self.incoming) {
            self.attachmentUploadView = [[AttachmentUploadView alloc] initWithAttachment:self.attachment
                                                                               superview:imageView
                                                                 attachmentStateCallback:nil];
        }
    }

    return self.cachedImageView;
}

- (CGSize)mediaViewDisplaySize {
    return [self ows_adjustBubbleSize:[super mediaViewDisplaySize] forImageSize:self.imageSize];
}

#pragma mark - OWSMessageEditing Protocol

- (BOOL)canPerformEditingAction:(SEL)action
{
    return (action == @selector(copy:) || action == NSSelectorFromString(@"save:"));
}

- (void)performEditingAction:(SEL)action
{
    NSString *actionString = NSStringFromSelector(action);

    if (action == @selector(copy:)) {
        // We should always copy to the pasteboard as data, not an UIImage.
        // The pasteboard should have as specific as UTI type as possible and
        // data support should be far more general than UIImage support.

        NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachment.contentType];
        if (!utiType) {
            OWSAssert(0);
            utiType = (NSString *)kUTTypeImage;
        }
        NSData *data = [NSData dataWithContentsOfURL:self.attachment.mediaURL];
        if (!data) {
            DDLogError(@"%@ Could not load image data: %@", [self tag], [self.attachment mediaURL]);
            OWSAssert(0);
            return;
        }
        [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
        return;
    } else if (action == NSSelectorFromString(@"save:")) {
        NSData *data = [NSData dataWithContentsOfURL:[self.attachment mediaURL]];
        if (!data) {
            DDLogError(@"%@ Could not load image data: %@", [self tag], [self.attachment mediaURL]);
            OWSAssert(0);
            return;
        }
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        [library writeImageDataToSavedPhotosAlbum:data
                                         metadata:nil
                                  completionBlock:^(NSURL *assetURL, NSError *error) {
                                      if (error) {
                                          DDLogWarn(@"Error Saving image to photo album: %@", error);
                                      }
                                  }];
        return;
    }
    
    // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
    DDLogError(@"'%@' action unsupported for %@: attachmentId=%@", actionString, self.class, self.attachmentId);
    OWSAssert(NO);
}

#pragma mark - OWSMessageMediaAdapter

- (void)setCellVisible:(BOOL)isVisible
{
    // Ignore.
}

- (void)clearCachedMediaViewsIfLastPresentingCell:(id)cell
{
    OWSAssert(cell);

    if (cell == self.lastPresentingCell) {
        [self clearCachedMediaViews];
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
