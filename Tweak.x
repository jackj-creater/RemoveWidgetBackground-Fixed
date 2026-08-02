#import <UIKit/UIKit.h>

// 递归清除所有子视图中的硬编码背景色与毛玻璃遮罩
static void cleanWidgetBackground(UIView *view) {
    if (!view) return;
    
    // 隐藏系统级与第三方毛玻璃层
    if ([view isKindOfClass:NSClassFromString(@"_UIVisualEffectView")] || 
        [view isKindOfClass:NSClassFromString(@"MTMaterialView")]) {
        view.hidden = YES;
        view.alpha = 0.0;
    }
    
    // 清除微博等第三方 App 在 View 内部硬编码的背景色
    if (view.backgroundColor && ![view.backgroundColor isEqual:[UIColor clearColor]]) {
        view.backgroundColor = [UIColor clearColor];
    }
    
    for (UIView *subview in view.subviews) {
        cleanWidgetBackground(subview);
    }
}

%hook SBHWidgetContainerView

- (void)layoutSubviews {
    %orig;
    
    // 强转 self 为 UIView，解决前置声明无法调用 Objective-C 方法的问题
    UIView *selfView = (UIView *)self;
    
    // 隐藏系统外壳底板
    UIView *materialView = [selfView valueForKey:@"_materialView"];
    if (materialView) {
        materialView.hidden = YES;
    }
    
    // 清除组件内部自绘背景
    cleanWidgetBackground(selfView);
}

%end

// 动态 Hook 负一屏宿主，修复丢失底板后的暗色模式错乱
%group FixDarkMode
%hook UIViewController

- (void)viewDidLoad {
    %orig;
    if ([NSStringFromClass([self class]) isEqualToString:@"CHUISWidgetHostViewController"]) {
        if ([self respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
            self.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        }
    }
}

%end
%end

%ctor {
    %init(FixDarkMode);
    %init(_ungrouped);
}
