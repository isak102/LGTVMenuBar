import Testing
@testable import LGTVMenuBar

@Suite("Scrollable Slider Tests")
@MainActor
struct ScrollableNSSliderTests {
    @Test("scrolling changes the slider value within its bounds")
    func scrollingChangesValueWithinBounds() {
        #expect(ScrollableNSSlider.scrolledValue(0.5, deltaY: 1, min: 0, max: 1) == 0.51)
        #expect(ScrollableNSSlider.scrolledValue(0, deltaY: -1, min: 0, max: 1) == 0)
        #expect(ScrollableNSSlider.scrolledValue(1, deltaY: 1, min: 0, max: 1) == 1)
    }
}
