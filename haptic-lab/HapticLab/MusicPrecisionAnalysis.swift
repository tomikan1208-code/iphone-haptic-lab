import Accelerate
import Foundation

struct MusicPrecisionFeature {
    let sub: Double
    let kick: Double
    let body: Double
    let lowFlux: Double
    let midFlux: Double
    let highFlux: Double
}

// Long windows resolve bass notes; a centered short window follows attacks without
// smearing them over the 93 ms bass window. Never sum left/right waveforms.
final class MusicPrecisionProcessor {
    private static let rate = 44_100.0
    private static let longSize = 4_096
    private static let shortSize = 1_024
    private let channels: Int
    private let longSetup: OpaquePointer
    private let shortSetup: OpaquePointer
    private var longWindow = [Float](repeating: 0, count: longSize)
    private var shortWindow = [Float](repeating: 0, count: shortSize)
    private var previous: [[Float]]
    private var longReal = [Float](repeating: 0, count: longSize)
    private var longOut = [Float](repeating: 0, count: longSize)
    private var longImaginaryOut = [Float](repeating: 0, count: longSize)
    private let longZero = [Float](repeating: 0, count: longSize)
    private var shortReal = [Float](repeating: 0, count: shortSize)
    private var shortOut = [Float](repeating: 0, count: shortSize)
    private var shortImaginaryOut = [Float](repeating: 0, count: shortSize)
    private let shortZero = [Float](repeating: 0, count: shortSize)

    init(channels: Int) throws {
        guard let long = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.longSize), .FORWARD) else {
            throw MusicError.unsupportedMedia
        }
        guard let short = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.shortSize), .FORWARD) else {
            vDSP_DFT_DestroySetup(long)
            throw MusicError.unsupportedMedia
        }
        self.channels = channels
        longSetup = long
        shortSetup = short
        previous = Array(repeating: Array(repeating: 0, count: Self.shortSize / 2), count: channels)
        vDSP_hann_window(&longWindow, vDSP_Length(Self.longSize), Int32(vDSP_HANN_NORM))
        vDSP_hann_window(&shortWindow, vDSP_Length(Self.shortSize), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_DFT_DestroySetup(longSetup); vDSP_DFT_DestroySetup(shortSetup) }

    func measure(_ samples: [Float], offset: Int, time: Double) -> MusicAudioFeature {
        var rms = 0.0, sub = 0.0, kick = 0.0, body = 0.0, mid = 0.0, high = 0.0
        var lowFlux = 0.0, midFlux = 0.0, highFlux = 0.0, brightness = 0.0
        var bands = Array(repeating: 0.0, count: MusicFrequencyBands.count)
        for channel in 0..<channels {
            for index in 0..<Self.longSize {
                longReal[index] = samples[offset + index * channels + channel] * longWindow[index]
            }
            vDSP_DFT_Execute(longSetup, longReal, longZero, &longOut, &longImaginaryOut)
            var energies = Array(repeating: 0.0, count: 5)
            var bandPower = Array(repeating: 0.0, count: MusicFrequencyBands.count)
            for bin in 1..<(Self.longSize / 2) {
                let frequency = Double(bin) * Self.rate / Double(Self.longSize)
                let power = Double(longOut[bin] * longOut[bin] + longImaginaryOut[bin] * longImaginaryOut[bin])
                if (30..<70).contains(frequency) { energies[0] += power }
                else if (70..<140).contains(frequency) { energies[1] += power }
                else if (140..<300).contains(frequency) { energies[2] += power }
                else if (300..<2_000).contains(frequency) { energies[3] += power }
                else if (2_000...8_000).contains(frequency) { energies[4] += power }
                if let band = MusicFrequencyBands.index(for: frequency) { bandPower[band] += power }
            }
            sub += sqrt(energies[0]) / Double(Self.longSize)
            kick += sqrt(energies[1]) / Double(Self.longSize)
            body += sqrt(energies[2]) / Double(Self.longSize)
            mid += sqrt(energies[3]) / Double(Self.longSize)
            high += sqrt(energies[4]) / Double(Self.longSize)
            for band in bands.indices { bands[band] += sqrt(bandPower[band]) / Double(Self.longSize) }
            var energy = 0.0
            let centerOffset = (Self.longSize - Self.shortSize) / 2
            for index in 0..<Self.shortSize {
                let sample = samples[offset + (centerOffset + index) * channels + channel]
                energy += Double(sample * sample)
                shortReal[index] = sample * shortWindow[index]
            }
            rms += sqrt(energy / Double(Self.shortSize))
            vDSP_DFT_Execute(shortSetup, shortReal, shortZero, &shortOut, &shortImaginaryOut)
            var magnitudeSum = 0.0, weightedSum = 0.0
            for bin in 1..<(Self.shortSize / 2) {
                let frequency = Double(bin) * Self.rate / Double(Self.shortSize)
                let magnitude = sqrt(shortOut[bin] * shortOut[bin] + shortImaginaryOut[bin] * shortImaginaryOut[bin])
                let increase = Double(max(0, magnitude - previous[channel][bin])) / Double(Self.shortSize)
                if (30..<300).contains(frequency) { lowFlux += increase }
                else if (300..<2_000).contains(frequency) { midFlux += increase }
                else if (2_000...8_000).contains(frequency) { highFlux += increase }
                if frequency <= 8_000 {
                    magnitudeSum += Double(magnitude)
                    weightedSum += Double(magnitude) * frequency
                }
                previous[channel][bin] = magnitude
            }
            brightness += magnitudeSum > 0 ? weightedSum / magnitudeSum / 6_000 : 0
        }
        let divisor = Double(channels)
        let detail = MusicPrecisionFeature(sub: sub / divisor, kick: kick / divisor, body: body / divisor,
            lowFlux: lowFlux / divisor, midFlux: midFlux / divisor, highFlux: highFlux / divisor)
        return MusicAudioFeature(time: time, rms: rms / divisor, bass: (sub + kick + body) / divisor,
            flux: (lowFlux + midFlux + highFlux) / divisor, brightness: min(1, brightness / divisor),
            mid: mid / divisor, high: high / divisor, bands: bands.map { $0 / divisor }, detail: detail)
    }

    static func makeTrack(features: [MusicAudioFeature], duration: Double, hash: String) throws -> MusicHapticTrack {
        let frames = features.filter { $0.time < duration }
        guard !frames.isEmpty, frames.contains(where: { $0.rms > 0.000_03 }),
              frames.allSatisfy({ $0.detail != nil }) else { throw MusicError.emptyAudio }
        let details = frames.compactMap(\.detail)
        func reference(_ values: [Double]) -> Double {
            let positive = values.filter { $0 > 0.000_01 }.sorted()
            return positive.isEmpty ? 0.000_01 : max(0.000_01, positive[Int(Double(positive.count - 1) * 0.95)])
        }
        let energyScale = reference(frames.map(\.rms))
        // A shared low-band reference preserves balance rather than amplifying tiny leakage in every band.
        let lowScale = max(reference(details.map { max($0.sub, $0.kick, $0.body) }), energyScale * 0.08)
        let midScale = max(reference(frames.map(\.mid)), energyScale * 0.03)
        let highScale = max(reference(frames.map(\.high)), energyScale * 0.03)
        let fluxScales = [reference(details.map(\.lowFlux)), reference(details.map(\.midFlux)), reference(details.map(\.highFlux))]
        let fluxFloor = reference(frames.map(\.flux)) * 0.06
        let spectrumScale = max(reference(frames.map { $0.bands.max() ?? 0 }), energyScale * 0.35)
        let fluxes = details.map { [$0.lowFlux, $0.midFlux, $0.highFlux] }
        var smooth = Array(repeating: 0.0, count: 6)
        var envelope: [MusicEnvelopePoint] = [], taps: [MusicTap] = [], spectrum: [MusicSpectrumFrame] = []
        for (index, frame) in frames.enumerated() {
            try Task.checkCancellation()
            let detail = details[index]
            let audible = frame.rms > 0.000_03
            func normalized(_ value: Double, scale: Double) -> Double {
                guard audible, value > max(0.000_001, frame.rms * 0.005) else { return 0 }
                return min(1, pow(value / scale, 0.7))
            }
            let values = [normalized(detail.sub, scale: lowScale), normalized(detail.kick, scale: lowScale),
                          normalized(detail.body, scale: lowScale), normalized(frame.rms, scale: energyScale),
                          normalized(frame.mid, scale: midScale), normalized(frame.high, scale: highScale)]
            for band in smooth.indices {
                smooth[band] += (values[band] - smooth[band]) * (values[band] > smooth[band] ? 0.62 : 0.30)
                if !audible { smooth[band] = 0 }
            }
            let texture = MusicLowTexture(sub: smooth[0], kick: smooth[1], body: smooth[2])
            let bass = min(1, texture.sub * 0.70 + texture.kick * 0.55 + texture.body * 0.25)
            let sharpness = audible ? min(1, 0.10 + smooth[5] * 0.55 + frame.brightness * 0.15) : 0
            envelope.append(.init(time: frame.time, bass: bass, energy: smooth[3], sharpness: sharpness,
                                  mid: smooth[4], high: smooth[5], texture: texture))
            spectrum.append(.init(time: frame.time, levels: frame.bands.map {
                audible ? (min(1, pow($0 / spectrumScale, 0.7)) * 1_000).rounded() / 1_000 : 0
            }))
            // Independent adaptive onset tests. When simultaneous, keep the dominant
            // attack: one actuator cannot make three separate taps at the same instant.
            var candidate: (band: Int, strength: Double)?
            for band in 0..<3 {
                let flux = fluxes[index][band]
                let local = fluxes[max(0, index - 50)..<index].map { $0[band] }
                let mean = local.isEmpty ? 0 : local.reduce(0, +) / Double(local.count)
                let variance = local.isEmpty ? 0 : local.reduce(0) { $0 + pow($1 - mean, 2) } / Double(local.count)
                let threshold = max(fluxFloor, fluxScales[band] * 0.16, mean + sqrt(variance) * 0.75)
                let before = index > 0 ? fluxes[index - 1][band] : 0
                let after = index + 1 < frames.count ? fluxes[index + 1][band] : 0
                let strength = flux * [1.2, 1.0, 0.7][band]
                if audible, flux > max(threshold, frame.rms * 0.025), flux > before, flux >= after,
                   strength > (candidate?.strength ?? 0) { candidate = (band, strength) }
            }
            if let candidate, frame.time - (taps.last?.time ?? -1) >= 0.1 {
                let band = candidate.band
                let onset = min(1, fluxes[index][band] / fluxScales[band])
                let intensity = ([0.45, 0.25, 0.15][band] + onset * [0.55, 0.40, 0.25][band]) * sqrt(values[3])
                taps.append(.init(time: frame.time, intensity: intensity, sharpness: [0.18, 0.55, 0.92][band]))
            }
        }
        let last = envelope[envelope.count - 1]
        envelope.append(.init(time: duration, bass: last.bass, energy: last.energy, sharpness: last.sharpness,
                              mid: last.mid, high: last.high, texture: last.texture))
        spectrum.append(.init(time: duration, levels: spectrum[spectrum.count - 1].levels))
        var track = MusicHapticTrack(version: MusicHapticTrack.currentVersion, audioSHA256: hash,
                                   duration: duration, envelope: envelope, taps: taps)
        track.spectrum = spectrum
        return try track.validated()
    }
}
