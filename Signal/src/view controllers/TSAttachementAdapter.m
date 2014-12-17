//
//  TSAttachementAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSAttachementAdapter.h"

#import "JSQMessagesMediaViewBubbleImageMasker.h"

@interface TSAttachementAdapter ()

@property UIImage *image;

@property (strong, nonatomic) UIImageView *cachedImageView;

@property (assign, nonatomic, readonly) BOOL isImageAttachment;

@end

@implementation TSAttachementAdapter

- (instancetype)initWithAttachement:(TSAttachementStream*)attachement{
    self = [super init];
    
    if (self) {
        _image = [UIImage imageWithCGImage:attachement.image.CGImage];
        _cachedImageView = nil;
        _isImageAttachment = YES;
    }
    return self;
}

- (void)dealloc
{
    _image = nil;
    _cachedImageView = nil;
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

#pragma mark - JSQMessageMediaData protocol

- (UIView *)mediaView
{
    if (self.image == nil) {
        return nil;
    }
    
    if (self.cachedImageView == nil) {
        CGSize size = [self mediaViewDisplaySize];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];
        imageView.frame = CGRectMake(0.0f, 0.0f, size.width, size.height);
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        [JSQMessagesMediaViewBubbleImageMasker applyBubbleImageMaskToMediaView:imageView isOutgoing:self.appliesMediaViewMaskAsOutgoing];
        self.cachedImageView = imageView;
    }
    
    return self.cachedImageView;
}

-(BOOL)isImage
{
    return _isImageAttachment;
}

@end
