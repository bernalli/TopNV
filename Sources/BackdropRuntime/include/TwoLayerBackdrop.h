#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
/// Installs an opaque pair on the attached glyph layer and restores its previous state on removal.
@interface KOTwoLayerBackdrop : NSObject
@property(nonatomic, readonly) CALayer *pressed;
- (BOOL)recommit:(NSString * _Nullable * _Nullable)reason;
- (void)remove;
@end
KOTwoLayerBackdrop * _Nullable KOInstallTwoLayer(CALayer *glyph, const float glyphMatrix[_Nonnull 20],
                                                NSArray<NSNumber *> *curve, const float threshold[_Nonnull 20],
                                                float level, NSString * _Nullable * _Nullable reason);
NS_ASSUME_NONNULL_END
