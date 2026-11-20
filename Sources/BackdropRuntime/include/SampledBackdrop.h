#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
/// Owns the ordinary filter while the render server supplies unfiltered luma changes.
@interface KOSampledBackdrop : NSObject <CALayerDelegate>
/// Fixed lamp filters still work when luma callbacks are unavailable.
+ (nullable instancetype)untracked:(CALayer *)layer;
+ (nullable instancetype)observe:(CALayer *)layer
                          sample:(void (^)(CALayer *, double, CFTimeInterval))sample;
// Render-server delegate messages. Protected content invalidates the last usable sample.
- (void)backdropLayer:(CALayer *)layer didChangeLuma:(double)luma;
- (void)backdropLayer:(CALayer *)layer didSampleProtectedLuma:(BOOL)protectedLuma;
/// Re-arm input tracking on the same attached layer. Success means the request was issued.
- (BOOL)forceSample;
- (BOOL)stopTracking;
/// A null matrix restores the original filter object.
- (BOOL)applyMatrix:(nullable const float *)values count:(size_t)count;
@end
NS_ASSUME_NONNULL_END
