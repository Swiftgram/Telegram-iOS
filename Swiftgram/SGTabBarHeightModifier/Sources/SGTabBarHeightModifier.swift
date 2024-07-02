import Foundation
import Display

public func sgTabBarHeightModifier(showTabNames: Bool, tabBarHeight: CGFloat, layout: ContainerViewLayout, defaultBarSmaller: Bool) -> CGFloat {
    var tabBarHeight = tabBarHeight
    guard !showTabNames else {
        return tabBarHeight
    }
    
    if defaultBarSmaller {
        tabBarHeight -= 6.0
    } else {
        tabBarHeight -= 12.0
    }
    
    if layout.intrinsicInsets.bottom.isZero {
        // Devices with home button need a bit more space
        if defaultBarSmaller {
            tabBarHeight += 3.0
        } else {
            tabBarHeight += 6.0
        }
    }
    
    return tabBarHeight
}
