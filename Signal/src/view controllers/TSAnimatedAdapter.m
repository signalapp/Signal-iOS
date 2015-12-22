//
//  TSAnimatedAdapter.m
//  Signal
//
//  Created by Mike Okner (@mikeokner) on 2015-09-01.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSAnimatedAdapter.h"

#import "FLAnimatedImage.h"
#import "JSQMessagesMediaViewBubbleImageMasker.h"
#import "UIDevice+TSHardwareVersion.h"

@interface TSAnimatedAdapter ()

@property (strong, nonatomic) UIImageView *cachedImageView;
@property (strong, nonatomic) NSData *fileData;
@property (strong, nonatomic) UIImage *image;
@property (strong, nonatomic) TSAttachmentStream *attachment;

@end

@implementation TSAnimatedAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment {
    self = [super init];

    if (self) {
        _cachedImageView = nil;
        _attachment      = attachment;
        _attachmentId    = attachment.uniqueId;
        _image           = [attachment image];
        _fileData        = [NSData dataWithContentsOfURL:[attachment mediaURL]];
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
    }

    return self.cachedImageView;
}

- (CGSize)mediaViewDisplaySize {
    return [self getBubbleSizeForImage:self.image];
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

#pragma mark - Utility

- (CGSize)getBubbleSizeForImage:(UIImage *)image {
    CGFloat aspectRatio = image.size.height / image.size.width;

    if ([[UIDevice currentDevice] isiPhoneVersionSixOrMore]) {
        return [self getLargeSizeForAspectRatio:aspectRatio];
    } else {
        return [self getSmallSizeForAspectRatio:aspectRatio];
    }
}

- (CGSize)getLargeSizeForAspectRatio:(CGFloat)ratio {
    return ratio > 1.0f ? [self largePortraitSize] : [self largeLandscapeSize];
}

- (CGSize)getSmallSizeForAspectRatio:(CGFloat)ratio {
    return ratio > 1.0f ? [self smallPortraitSize] : [self smallLandscapeSize];
}

- (CGSize)largePortraitSize {
    return CGSizeMake(220.0f, 310.0f);
}

- (CGSize)smallPortraitSize {
    return CGSizeMake(150.0f, 210.0f);
}

- (CGSize)largeLandscapeSize {
    return CGSizeMake(310.0f, 220.0f);
}

- (CGSize)smallLandscapeSize {
    return CGSizeMake(210.0f, 150.0f);
}

@end
