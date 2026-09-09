import Testing
@testable import LGTVMenuBar

@Suite("TV Keyboard Input Tests")
struct TVKeyboardInputTests {
    @Test("maps text and remote keys")
    func mapsTextAndRemoteKeys() {
        #expect(TVKeyboardInput.from(characters: "A", keyCode: 0) == .text("A"))
        #expect(TVKeyboardInput.from(characters: "", keyCode: 51) == .delete)
        #expect(TVKeyboardInput.from(characters: "\r", keyCode: 36) == .enter)
        #expect(TVKeyboardInput.from(characters: "", keyCode: 126) == .navigation(.up))
        #expect(TVKeyboardInput.from(characters: "", keyCode: 125) == .navigation(.down))
        #expect(TVKeyboardInput.from(characters: "\t", keyCode: 48) == nil)
    }
}
