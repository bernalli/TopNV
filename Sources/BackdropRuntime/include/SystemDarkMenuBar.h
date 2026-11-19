#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Own one client connection for the entire probe, including the final restore.
@interface SystemDarkMenuBarClient : NSObject
+ (nullable instancetype)resolve;
- (void)request:(BOOL)enabled completion:(void (^)(NSString * _Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
