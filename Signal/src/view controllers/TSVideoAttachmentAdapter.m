//
//  TSAttachementAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSVideoAttachmentAdapter.h"

#import "UIDevice+TSHardwareVersion.h"
#import "JSQMessagesMediaViewBubbleImageMasker.h"

@interface TSVideoAttachmentAdapter ()

@property UIImage *image;

@property (strong, nonatomic) UIImageView *cachedImageView;
@end

@implementation TSVideoAttachmentAdapter

- (instancetype)initWithAttachment:(TSAttachmentStream*)attachment{
    self = [super initWithFileURL:[attachment videoURL] isReadyToPlay:YES];
    
    if (self) {
        _image           = attachment.image;
        _cachedImageView = nil;
        _attachmentId    = attachment.uniqueId;
        _contentType     = attachment.contentType;
        
    }
    return self;
}

-(BOOL) isImage{
    return NO;
}

-(BOOL) isAudio {
    return [_contentType containsString:@"audio/"];
}


-(BOOL) isVideo {
    return [_contentType containsString:@"video/"];
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
        UIImage *img = [UIImage imageNamed:@"play_button"];
        UIImageView *playButton = [[UIImageView alloc] initWithImage:img];
        playButton.frame = CGRectMake((size.width/2)-18, (size.height/2)-18, 37, 37);
        [self.cachedImageView addSubview:playButton];
        CALayer *sublayer = [CALayer layer];
        [sublayer setBackgroundColor:[UIColor blackColor].CGColor];
        [sublayer setOpacity:0.4f];
        [sublayer setFrame:self.cachedImageView.frame];
        //[self.cachedImageView.layer addSublayer:sublayer];
    }
    
    return self.cachedImageView;
}

- (void)dealloc {
    _image = nil;
    _cachedImageView = nil;
}

- (void)setAppliesMediaViewMaskAsOutgoing:(BOOL)appliesMediaViewMaskAsOutgoing
{
    [super setAppliesMediaViewMaskAsOutgoing:appliesMediaViewMaskAsOutgoing];
    _cachedImageView = nil;
}

@end
