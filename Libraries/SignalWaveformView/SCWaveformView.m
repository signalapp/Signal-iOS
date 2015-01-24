//
//  SCWaveformView.m
//  SCWaveformView
//
//  Created by Simon CORSIN on 24/01/14.
//  Copyright (c) 2014 Simon CORSIN. All rights reserved.
//

#import "SCWaveformView.h"

#define absX(x) (x < 0 ? 0 - x : x)
#define minMaxX(x, mn, mx) (x <= mn ? mn : (x >= mx ? mx : x))
#define noiseFloor (-50.0)
#define decibel(amplitude) (20.0 * log10(absX(amplitude) / 32767.0))

@interface SCWaveformView() {
    UIImageView *_normalImageView;
    UIImageView *_progressImageView;
    UIView *_cropNormalView;
    UIView *_cropProgressView;
    BOOL _normalColorDirty;
    BOOL _progressColorDirty;
}

@end

@implementation SCWaveformView

- (instancetype)init {
    self = [super init];
    
    if (self) {
        [self commonInit];
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self commonInit];
    }
    
    return self;
}

- (void)commonInit
{
    _normalImageView = [[UIImageView alloc] init];
    _progressImageView = [[UIImageView alloc] init];
    _cropNormalView = [[UIView alloc] init];
    _cropProgressView = [[UIView alloc] init];
    
    _cropNormalView.clipsToBounds = YES;
    _cropProgressView.clipsToBounds = YES;
    
    [_cropNormalView addSubview:_normalImageView];
    [_cropProgressView addSubview:_progressImageView];
    
    [self addSubview:_cropNormalView];
    [self addSubview:_cropProgressView];
    
    self.normalColor = [UIColor blueColor];
    self.progressColor = [UIColor redColor];
    
    _normalColorDirty = NO;
    _progressColorDirty = NO;
}

void SCRenderPixelWaveformInContext(CGContextRef context, float halfGraphHeight, double sample, float x)
{
    float pixelHeight = halfGraphHeight * (1 - sample / noiseFloor);
    
    if (pixelHeight <= 1) {
        pixelHeight = 1;
    }
    
    CGRect rect = CGRectMake(x, halfGraphHeight-pixelHeight, 4, pixelHeight*2);
    CGPathRef path = CGPathCreateWithRect(rect, NULL);
    CGContextAddPath(context, path);
    CGContextDrawPath(context, kCGPathFill);

}

+ (void)renderWaveformInContext:(CGContextRef)context asset:(AVAsset *)asset withColor:(UIColor *)color andSize:(CGSize)size antialiasingEnabled:(BOOL)antialiasingEnabled
{
    if (asset == nil) {
        return;
    }
    
    CGFloat pixelRatio = [UIScreen mainScreen].scale;
    size.width *= pixelRatio;
    size.height *= pixelRatio;
    
    CGFloat widthInPixels = size.width;
    CGFloat heightInPixels = size.height;
    float halfGraphHeight = (float)(heightInPixels / 2);
    
    CGContextSetAllowsAntialiasing(context, antialiasingEnabled);
    CGContextSetLineWidth(context, 1.0);
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetFillColorWithColor(context, color.CGColor);
    
    NSError *error = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    
    NSArray *audioTrackArray = [asset tracksWithMediaType:AVMediaTypeAudio];
    
    if (audioTrackArray.count == 0) {
        return;
    }
    
    AVAssetTrack *songTrack = [audioTrackArray objectAtIndex:0];
    
    NSDictionary *outputSettingsDict = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                        [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
                                        [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                                        [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey,
                                        [NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
                                        nil];
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:songTrack outputSettings:outputSettingsDict];
    [reader addOutput:output];
    
    UInt32 channelCount;
    NSArray *formatDesc = songTrack.formatDescriptions;
    for (unsigned int i = 0; i < [formatDesc count]; ++i) {
        CMAudioFormatDescriptionRef item = (__bridge CMAudioFormatDescriptionRef)[formatDesc objectAtIndex:i];
        const AudioStreamBasicDescription* fmtDesc = CMAudioFormatDescriptionGetStreamBasicDescription(item);
        
        if (fmtDesc == nil) {
            return;
        }
        
        channelCount = fmtDesc->mChannelsPerFrame;
    }
    
    UInt32 bytesPerInputSample = 2 * channelCount;
    unsigned long int totalSamples = (unsigned long int)asset.duration.value;
    NSUInteger samplesPerPixel = totalSamples / (widthInPixels);
    samplesPerPixel = samplesPerPixel < 1 ? 1 : samplesPerPixel;
    [reader startReading];
    
    double bigSample = 0;
    NSUInteger bigSampleCount = 0;
    NSUInteger totalSampleCount = 0;
    NSMutableData * data = [NSMutableData dataWithLength:32768];
    
    int currentX = 0;
    while (reader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sampleBufferRef = [output copyNextSampleBuffer];
        
        if (sampleBufferRef) {
            CMBlockBufferRef blockBufferRef = CMSampleBufferGetDataBuffer(sampleBufferRef);
            size_t bufferLength = CMBlockBufferGetDataLength(blockBufferRef);
            
            if (data.length < bufferLength) {
                [data setLength:bufferLength];
            }
            
            CMBlockBufferCopyDataBytes(blockBufferRef, 0, bufferLength, data.mutableBytes);
            
            SInt16 *samples = (SInt16 *)data.mutableBytes;
            int sampleCount = (int)(bufferLength / bytesPerInputSample);
            for (int i = 0; i < sampleCount; i++) {
                Float32 sample = (Float32) *samples++;
                sample = decibel(sample);
                sample = minMaxX(sample, noiseFloor, 0);
                
                for (int j = 1; j < channelCount; j++)
                    samples++;
                
                bigSample += sample;
                bigSampleCount++;
                totalSampleCount++;
                
                if (bigSampleCount == samplesPerPixel) {
                    
                    if (currentX % 6
                        == 0) {
                        double averageSample = bigSample / (double)bigSampleCount;
                        
                        
                        
                        //if (((totalSamples - totalSampleCount) / samplesPerPixel) > 13) {
                            SCRenderPixelWaveformInContext(context, halfGraphHeight, averageSample, currentX);
                        //}
                    }
                    currentX ++;
                    bigSample = 0;
                    bigSampleCount  = 0;
                }
            }
            CMSampleBufferInvalidate(sampleBufferRef);
            CFRelease(sampleBufferRef);
        }
    }
}

+ (UIImage*)generateWaveformImage:(AVAsset *)asset withColor:(UIColor *)color andSize:(CGSize)size antialiasingEnabled:(BOOL)antialiasingEnabled
{
    CGFloat ratio = [UIScreen mainScreen].scale;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size.width * ratio, size.height * ratio), NO, 1);
    
    [SCWaveformView renderWaveformInContext:UIGraphicsGetCurrentContext() asset:asset withColor:color andSize:size antialiasingEnabled:antialiasingEnabled];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return image;
}

+ (UIImage*)recolorizeImage:(UIImage*)image withColor:(UIColor*)color
{
    CGRect imageRect = CGRectMake(0, 0, image.size.width, image.size.height);
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, 0.0, image.size.height);
    CGContextScaleCTM(context, 1.0, -1.0);
    CGContextDrawImage(context, imageRect, image.CGImage);
    [color set];
    UIRectFillUsingBlendMode(imageRect, kCGBlendModeSourceAtop);
    
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return newImage;
}

- (void)generateWaveforms
{
    CGRect rect = self.bounds;
    
    if (self.generatedNormalImage == nil && self.asset) {
        self.generatedNormalImage = [SCWaveformView generateWaveformImage:self.asset withColor:self.normalColor andSize:CGSizeMake(rect.size.width, rect.size.height) antialiasingEnabled:self.antialiasingEnabled];
        _normalColorDirty = NO;
    }
    
    if (self.generatedNormalImage != nil) {
        if (_normalColorDirty) {
            self.generatedNormalImage = [SCWaveformView recolorizeImage:self.generatedNormalImage withColor:self.normalColor];
            _normalColorDirty = NO;
        }
        
        if (_progressColorDirty || self.generatedProgressImage == nil) {
            self.generatedProgressImage = [SCWaveformView recolorizeImage:self.generatedNormalImage withColor:self.progressColor];
            _progressColorDirty = NO;
        }
    }
 
}

- (void)drawRect:(CGRect)rect
{
    [self generateWaveforms];
    [super drawRect:rect];
}

- (void)applyProgressToSubviews
{
    CGRect bs = self.bounds;
    CGFloat progressWidth = bs.size.width * _progress;
    _cropProgressView.frame = CGRectMake(0, 0, progressWidth, bs.size.height);
    _cropNormalView.frame = CGRectMake(progressWidth, 0, bs.size.width - progressWidth, bs.size.height);
    _normalImageView.frame = CGRectMake(-progressWidth, 0, bs.size.width, bs.size.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect bs = self.bounds;
    _normalImageView.frame = bs;
    _progressImageView.frame = bs;
    
    // If the size is now bigger than the generated images
    if (bs.size.width > self.generatedNormalImage.size.width) {
        self.generatedNormalImage = nil;
        self.generatedProgressImage = nil;
    }
    
    [self applyProgressToSubviews];
}

- (void)setNormalColor:(UIColor *)normalColor
{
    _normalColor = normalColor;
    _normalColorDirty = YES;
    [self setNeedsDisplay];
}

- (void)setProgressColor:(UIColor *)progressColor
{
    _progressColor = progressColor;
    _progressColorDirty = YES;
    [self setNeedsDisplay];
}

- (void)setAsset:(AVAsset *)asset
{
    _asset = asset;
    self.generatedProgressImage = nil;
    self.generatedNormalImage = nil;
    [self setNeedsDisplay];
}

- (void)setProgress:(CGFloat)progress
{
    _progress = progress;
    [self applyProgressToSubviews];
}

- (UIImage*)generatedNormalImage
{
    return _normalImageView.image;
}

- (void)setGeneratedNormalImage:(UIImage *)generatedNormalImage
{
    _normalImageView.image = generatedNormalImage;
}

- (UIImage*)generatedProgressImage
{
    return _progressImageView.image;
}

- (void)setGeneratedProgressImage:(UIImage *)generatedProgressImage
{
    _progressImageView.image = generatedProgressImage;
}

- (void)setAntialiasingEnabled:(BOOL)antialiasingEnabled
{
    if (_antialiasingEnabled != antialiasingEnabled) {
        _antialiasingEnabled = antialiasingEnabled;
        self.generatedProgressImage = nil;
        self.generatedNormalImage = nil;
        [self setNeedsDisplay];        
    }
}

@end
