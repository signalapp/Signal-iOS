//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAnimatedAdapter.h"
#import "AttachmentUploadView.h"
#import "FLAnimatedImage.h"
#import "JSQMediaItem+OWS.h"
#import "TSAttachmentStream.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>

@interface TSAnimatedAdapter ()

@property (nonatomic) UIImageView *cachedImageView;
@property (nonatomic) UIImage *image;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL incoming;

@end

@implementation TSAnimatedAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming
{
    self = [super init];

    if (self) {
        _cachedImageView = nil;
        _attachment      = attachment;
        _attachmentId    = attachment.uniqueId;
        _image           = [attachment image];
        _fileData        = [NSData dataWithContentsOfURL:[attachment mediaURL]];
        _incoming = incoming;
    }

    return self;
}

- (void)dealloc {
    _cachedImageView = nil;
    _attachment      = nil;
    _attachmentId    = nil;
    _image           = nil;
    _fileData        = nil;
}

- (void)clearCachedMediaViews {
    [super clearCachedMediaViews];
    _cachedImageView = nil;
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing {
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

#pragma mark - NSObject

- (NSUInteger)hash
{
    return super.hash ^ self.image.hash;
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView {
    if (self.cachedImageView == nil) {
        // Use Flipboard FLAnimatedImage library to display gifs
        FLAnimatedImage *animatedGif   = [FLAnimatedImage animatedImageWithGIFData:self.fileData];
        FLAnimatedImageView *imageView = [[FLAnimatedImageView alloc] init];
        imageView.animatedImage        = animatedGif;
        CGSize size                    = [self mediaViewDisplaySize];
        imageView.frame                = CGRectMake(0.0, 0.0, size.width, size.height);
        imageView.contentMode          = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds        = YES;
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
    if (action == @selector(copy:)) {
        UIPasteboard *pasteBoard = UIPasteboard.generalPasteboard;
        [pasteBoard setData:self.fileData forPasteboardType:(__bridge NSString *)kUTTypeGIF];
    } else if (action == NSSelectorFromString(@"save:")) {
        NSData *photoData = self.fileData;
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        [library writeImageDataToSavedPhotosAlbum:photoData
                                         metadata:nil
                                  completionBlock:^(NSURL *assetURL, NSError *error) {
                                      if (error) {
                                          DDLogWarn(@"Error Saving image to photo album: %@", error);
                                      }
                                  }];
    } else {
        // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
        NSString *actionString = NSStringFromSelector(action);
        DDLogError(@"'%@' action unsupported for %@: attachmentId=%@", actionString, [self class], self.attachmentId);
    }
}

@end
