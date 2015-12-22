//
//  TSAttachementAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSPhotoAdapter.h"

#import "JSQMessagesMediaViewBubbleImageMasker.h"
#import "UIDevice+TSHardwareVersion.h"

@interface TSPhotoAdapter ()

@property (strong, nonatomic) UIImageView *cachedImageView;
@end

@implementation TSPhotoAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment {
    self = [super initWithImage:attachment.image];

    if (self) {
        _cachedImageView = nil;
        _attachmentId    = attachment.uniqueId;
    }
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
