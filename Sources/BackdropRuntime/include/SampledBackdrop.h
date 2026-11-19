#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
/// Owns the ordinary filter while the render server supplies unfiltered luma changes.
@interface KOSampledBackdrop : NSObject <CALayerDelegate>
+ (nullable instancetype)observe:(CALayer *)layer
                          sample:(void (^)(CALayer *, double))sample;
// Render-server delegate messages. Protected content invalidates the last usable sample.
- (void)backdropLayer:(CALayer *)layer didChangeLuma:(double)luma;
- (void)backdropLayer:(CALayer *)layer didSampleProtectedLuma:(BOOL)protectedLuma;
- (BOOL)stopTracking;
/// A null matrix restores the original filter object.
- (BOOL)applyMatrix:(nullable const float *)values count:(size_t)count;
@end
NS_ASSUME_NONNULL_END
