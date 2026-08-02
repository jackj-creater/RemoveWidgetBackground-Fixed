#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 安全递归清除背景
static void safeCleanWidgetBackground(UIView *view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    
    // 隐藏毛玻璃材质层
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"VisualEffect"] || [className containsString:@"MTMaterialView"]) {
        view.hidden = YES;
        return;
    }
    
    // 避免对系统底层私有 View 强行改背景色
    if (![className hasPrefix:@"_UI"]) {
        if (view.backgroundColor && ![view.backgroundColor isEqual:[UIColor clearColor]]) {
            view.backgroundColor = [UIColor clearColor];
        }
    }
    
    // 安全递归（复制数组防止遍历中崩溃）
    NSArray *subviews = [view.subviews copy];
    for (UIView *subview in subviews) {
        safeCleanWidgetBackground(subview);
    }
}

%hook SBHWidgetContainerView

- (void)layoutSubviews {
    %orig;
    
    UIView *selfView = (UIView *)self;
    if (!selfView) return;
    
    // 使用 Runtime 方式获取 _materialView，彻底规避 KVC Exception 崩溃
    @try {
        Ivar ivar = class_getInstanceVariable([self class], "_materialView");
        if (ivar) {
            UIView *materialView = object_getIvar(self, ivar);
            if (materialView && [materialView isKindOfClass:[UIView class]]) {
                materialView.hidden = YES;
            }
        }
    } @catch (NSException *exception) {
        // 捕获异常
    }
    
    // 清理微博等第三方 App 内部背景
    safeCleanWidgetBackground(selfView);
}

%end

// 动态判断 Hook 负一屏宿主，避免静态 @interface 导致的 Clang 崩溃
%group FixDarkMode
%hook UIViewController

- (void)viewDidLoad {
    %orig;
    if ([NSStringFromClass([self class]) isEqualToString:@"CHUISWidgetHostViewController"]) {
        if ([self respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
            [self performSelector:@selector(setOverrideUserInterfaceStyle:) withObject:@(UIUserInterfaceStyleUnspecified)];
        }
    }
}

%end
%end

%ctor {
    %init(FixDarkMode);
    %init(_ungrouped);
}
