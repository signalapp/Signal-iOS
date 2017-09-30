//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAnimatedAdapter.h"
#import "AttachmentUploadView.h"
#import "JSQMediaItem+OWS.h"
#import "TSAttachmentStream.h"
#import "UIColor+OWS.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <JSQMessagesViewController/JSQMessagesMediaViewBubbleImageMasker.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/NSData+Image.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSAnimatedAdapter ()

@property (nonatomic, nullable) YYAnimatedImageView *cachedImageView;
@property (nonatomic) TSAttachmentStream *attachment;
@property (nonatomic, nullable) AttachmentUploadView *attachmentUploadView;
@property (nonatomic) BOOL incoming;
@property (nonatomic) CGSize imageSize;
@property (nonatomic) NSString *attachmentId;

// See comments on OWSMessageMediaAdapter.
@property (nonatomic, nullable, weak) id lastPresentingCell;

@end

#pragma mark -

@implementation TSAnimatedAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming
{
    self = [super init];

    if (self) {
        _cachedImageView = nil;
        _attachment      = attachment;
        _attachmentId    = attachment.uniqueId;
        _incoming = incoming;
        _imageSize = [attachment imageSizeWithoutTransaction];
    }

    return self;
}

- (void)clearAllViews
{
    OWSAssert([NSThread isMainThread]);

    [_cachedImageView removeFromSuperview];
    _cachedImageView = nil;
    _attachmentUploadView = nil;
}

- (void)clearCachedMediaViews {
    [super clearCachedMediaViews];
    [self clearAllViews];
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing {
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    [self clearAllViews];
}

#pragma mark - NSObject

- (NSUInteger)hash
{
    return super.hash ^ self.attachment.uniqueId.hash;
}

#pragma mark - OWSMessageMediaAdapter

- (void)setCellVisible:(BOOL)isVisible
{
    if (isVisible) {
        [self.cachedImageView startAnimating];
    } else {
        [self.cachedImageView stopAnimating];
    }
}

- (void)clearCachedMediaViewsIfLastPresentingCell:(id)cell
{
    OWSAssert(cell);

    if (cell == self.lastPresentingCell) {
        [self clearCachedMediaViews];
    }
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView {
    OWSAssert([NSThread isMainThread]);

    if (self.cachedImageView == nil) {
        NSString *_Nullable filePath = [self.attachment filePath];
        if (![NSData ows_isValidImageAtPath:filePath]) {
            return nil;
        }
        YYImage *_Nullable animatedGif = filePath ? [YYImage imageWithContentsOfFile:filePath] : nil;
        if (!animatedGif) {
            DDLogError(@"%@ Could not load image: %@", [self tag], filePath);
            UIView *view = [UIView new];
            view.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.f];
            return view;
        }
        YYAnimatedImageView *imageView = [[YYAnimatedImageView alloc] init];
        imageView.image = animatedGif;
        CGSize size                    = [self mediaViewDisplaySize];
        imageView.contentMode          = UIViewContentModeScaleAspectFill;
        imageView.frame                = CGRectMake(0.0, 0.0, size.width, size.height);
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
    return [self ows_adjustBubbleSize:[super mediaViewDisplaySize] forImageSize:self.imageSize];
}

#pragma mark - OWSMessageEditing Protocol

- (BOOL)canPerformEditingAction:(SEL)action
{
    return (action == @selector(copy:) || action == NSSelectorFromString(@"save:"));
}

- (void)performEditingAction:(SEL)action
{
    if (action == @selector(copy:)) {
        NSString *utiType = [MIMETypeUtil utiTypeForMIMEType:self.attachment.contentType];
        if (!utiType) {
            OWSFail(@"%@ Unknown MIME type: %@", self.tag, self.attachment.contentType);
            utiType = (NSString *)kUTTypeGIF;
        }

        NSData *data = [NSData dataWithContentsOfURL:[self.attachment mediaURL]];
        if (!data) {
            OWSFail(@"%@ Could not load image data: %@", [self tag], [self.attachment mediaURL]);
            return;
        }
        [UIPasteboard.generalPasteboard setData:data forPasteboardType:utiType];
    } else if (action == NSSelectorFromString(@"save:")) {
        NSData *data = [NSData dataWithContentsOfURL:[self.attachment mediaURL]];
        if (!data) {
            OWSFail(@"%@ Could not load image data: %@", [self tag], [self.attachment mediaURL]);
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
    } else {
        // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
        NSString *actionString = NSStringFromSelector(action);
        DDLogError(@"'%@' action unsupported for %@: attachmentId=%@", actionString, [self class], self.attachmentId);
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
