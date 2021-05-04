//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (normalizeImage)

- (UIImage *)normalizedImage;
- (UIImage *)resizedWithQuality:(CGInterpolationQuality)quality rate:(CGFloat)rate;

- (nullable UIImage *)resizedWithMaxDimensionPoints:(CGFloat)maxDimensionPoints;
- (nullable UIImage *)resizedWithMaxDimensionPixels:(CGFloat)maxDimensionPixels;
- (nullable UIImage *)resizedImageToSize:(CGSize)dstSize;
- (UIImage *)resizedImageToFillPixelSize:(CGSize)boundingSize;

+ (UIImage *)imageWithColor:(UIColor *)color;
+ (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size;
+ (nullable NSData *)validJpegDataFromAvatarData:(NSData *)avatarData;

@property (readonly) size_t pixelWidth;
@property (readonly) size_t pixelHeight;
@property (readonly) CGSize pixelSize;

@end

NS_ASSUME_NONNULL_END
