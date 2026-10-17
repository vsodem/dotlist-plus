import XCTest
@testable import DotListPlusUI

final class ThemeTests: XCTestCase {
    func testLaunchOverrideSelectsThemeAndUnknownValuesKeepDeveloperDefault() {
        XCTAssertEqual(ThemeConfiguration.resolve(environment: [:], fallback: .default).name, "Default")
        XCTAssertEqual(ThemeConfiguration.resolve(environment: ["DOTLIST_THEME": "tron"]).name, "TRON")
        XCTAssertEqual(ThemeConfiguration.resolve(environment: ["DOTLIST_THEME": "default"], fallback: .tron).name, "Default")
        XCTAssertEqual(ThemeConfiguration.resolve(environment: ["DOTLIST_THEME": "typo"], fallback: .tron).name, "TRON")
        XCTAssertEqual(ThemeConfiguration.resolve(environment: [:], fallback: .tron).name, "TRON")
    }

    func testReduceMotionSuppressesDecorativeAnimationForEveryTheme() {
        for theme in [AppTheme.default, .tron] {
            XCTAssertNil(theme.motion.animation(reduceMotion: true))
            XCTAssertEqual(theme.motion.pressedScale(reduceMotion: true), 1)
        }
        XCTAssertNil(AppTheme.default.motion.animation(reduceMotion: false))
        XCTAssertNotNil(AppTheme.tron.motion.animation(reduceMotion: false))
        XCTAssertLessThan(AppTheme.tron.motion.pressedScale(reduceMotion: false), 1)
    }
}
