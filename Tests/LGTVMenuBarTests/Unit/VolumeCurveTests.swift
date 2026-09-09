import Testing
@testable import LGTVMenuBar

/// Volume-scale conversion functions mirrored from `VolumeSection`.
enum VolumeScale {
    static func sliderToVolume(_ position: Double) -> Int {
        Int((position * 100).rounded())
    }

    static func volumeToSlider(_ volume: Int) -> Double {
        Double(volume) / 100
    }
}

@Suite("Volume Scale Tests")
struct VolumeScaleTests {
    @Test("slider positions map linearly to volume")
    func sliderToVolumeIsLinear() {
        #expect(VolumeScale.sliderToVolume(0) == 0)
        #expect(VolumeScale.sliderToVolume(0.25) == 25)
        #expect(VolumeScale.sliderToVolume(0.5) == 50)
        #expect(VolumeScale.sliderToVolume(0.75) == 75)
        #expect(VolumeScale.sliderToVolume(1) == 100)
    }

    @Test("volume values map linearly to slider positions")
    func volumeToSliderIsLinear() {
        #expect(VolumeScale.volumeToSlider(0) == 0)
        #expect(VolumeScale.volumeToSlider(25) == 0.25)
        #expect(VolumeScale.volumeToSlider(50) == 0.5)
        #expect(VolumeScale.volumeToSlider(75) == 0.75)
        #expect(VolumeScale.volumeToSlider(100) == 1)
    }

    @Test("volume scale round-trips")
    func roundTripsVolume() {
        for volume in 0...100 {
            #expect(VolumeScale.sliderToVolume(VolumeScale.volumeToSlider(volume)) == volume)
        }
    }
}
