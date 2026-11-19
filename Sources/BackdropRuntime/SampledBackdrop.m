#import "SampledBackdrop.h"
#import <objc/runtime.h>
#import <math.h>

@protocol KOFilterCatalog
+ (NSArray<NSString *> *)filterTypes;
@end

@implementation KOSampledBackdrop {
    __weak CALayer *_layer;
    NSArray *_ordinaryFilters;
    void (^_sample)(CALayer *, double);
}

static BOOL DelegateMatches(Class cls, SEL selector) {
    Protocol *protocol = NSProtocolFromString(@"CABackdropLayerDelegate");
    if (!protocol) return NO;
    struct objc_method_description method = protocol_getMethodDescription(protocol, selector, NO, YES);
    if (!method.types) method = protocol_getMethodDescription(protocol, selector, YES, YES);
    NSMethodSignature *expected = method.types ? [NSMethodSignature signatureWithObjCTypes:method.types] : nil;
    NSMethodSignature *actual = [cls instanceMethodSignatureForSelector:selector];
    if (!expected || !actual || expected.numberOfArguments != actual.numberOfArguments ||
        strcmp(expected.methodReturnType, actual.methodReturnType) != 0) return NO;
    for (NSUInteger i = 0; i < expected.numberOfArguments; i++) {
        if (strcmp([expected getArgumentTypeAtIndex:i], [actual getArgumentTypeAtIndex:i]) != 0) return NO;
    }
    return YES;
}

+ (instancetype)observe:(CALayer *)layer sample:(void (^)(CALayer *, double))sample {
    @try {
        Class<KOFilterCatalog> catalog = NSClassFromString(@"CAFilter");
        NSMethodSignature *signature = [(id)catalog methodSignatureForSelector:@selector(filterTypes)];
        if (![NSThread isMainThread] || signature.numberOfArguments != 2 ||
            strcmp(signature.methodReturnType, @encode(id)) != 0 ||
            ![[catalog filterTypes] containsObject:@"colorMatrix"] ||
            !DelegateMatches(self, @selector(backdropLayer:didChangeLuma:)) ||
            !DelegateMatches(self, @selector(backdropLayer:didSampleProtectedLuma:)) ||
            layer.delegate || layer.filters.count != 1 ||
            ![[layer.filters.firstObject valueForKey:@"type"] isEqual:@"colorMatrix"]) return nil;

        KOSampledBackdrop *source = [self new];
        source->_layer = layer;
        source->_ordinaryFilters = layer.filters;
        source->_sample = [sample copy];
        // Sample the input of this bar. Including our own keyed output would create feedback.
        [layer setValue:@NO forKey:@"allowsFilteredLuma"];
        [layer setValue:@YES forKey:@"tracksLuma"];
        if ([[layer valueForKey:@"allowsFilteredLuma"] boolValue] ||
            ![[layer valueForKey:@"tracksLuma"] boolValue]) return nil;
        layer.delegate = source;
        return layer.delegate == source ? source : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

- (void)backdropLayer:(CALayer *)layer didChangeLuma:(double)luma {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (layer.delegate == self) self->_sample(layer, luma);
    });
}

- (void)backdropLayer:(CALayer *)layer didSampleProtectedLuma:(BOOL)protectedLuma {
    if (protectedLuma) [self backdropLayer:layer didChangeLuma:NAN];
}

- (BOOL)applyMatrix:(const float *)values count:(size_t)count {
    CALayer *layer = _layer;
    if (!layer || ![NSThread isMainThread]) return NO;
    @try {
        NSArray *filters = _ordinaryFilters;
        if (values != NULL) {
            if (count != 20) return NO;
            id ordinary = _ordinaryFilters.firstObject;
            id filter = [ordinary copy];
            if (!filter || filter == ordinary) return NO;
            NSValue *matrix = [NSValue valueWithBytes:values objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
            [filter setValue:matrix forKey:@"inputColorMatrix"];
            if (![[filter valueForKey:@"inputColorMatrix"] isEqual:matrix]) return NO;
            filters = @[filter];
        }
        [CATransaction begin];
        @try {
            [CATransaction setDisableActions:YES];
            layer.filters = filters;
        } @finally {
            [CATransaction commit];
        }
        return layer.filters.count == 1 && layer.filters.firstObject == filters.firstObject;
    } @catch (NSException *exception) {
        return NO;
    }
}
- (BOOL)stopTracking {
    CALayer *layer = _layer;
    if (!layer) return YES;
    BOOL restored = [self applyMatrix:NULL count:0];
    @try {
        if (layer.delegate == self) {
            layer.delegate = nil;
            [layer setValue:@NO forKey:@"tracksLuma"];
        }
    } @catch (NSException *exception) {
        return NO;
    }
    return restored;
}
@end
