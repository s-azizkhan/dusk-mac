import AVFoundation

/// Tiny synthesized UI clicks (no audio files). Engine pauses when idle to save power.
final class Sound {
    static let shared = Sound()
    static var enabled: Bool { UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sr = 44_100.0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var idle: DispatchWorkItem?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Detent tick; pitch 0...1 maps low to high.
    func tick(_ pitch: Double = 0.5) { play(freq: 1500 + 1500 * pitch, ms: 7, gain: 0.22, noise: 0.25) }
    /// Firmer click when snapping to a preset or step.
    func snap() { play(freq: 2600, ms: 12, gain: 0.4, noise: 0.2) }
    /// Soft "tock" for button presses.
    func press() { play(freq: 520, ms: 22, gain: 0.45, noise: 0.35) }
    /// Rising chirp for on, falling for off.
    func toggle(_ on: Bool) { play(freq: on ? 760 : 1250, ms: 55, gain: 0.35, noise: 0.05, glide: on ? 520 : -520) }

    private func play(freq: Double, ms: Double, gain: Float, noise: Float, glide: Double = 0) {
        guard Sound.enabled else { return }
        let key = "\(Int(freq))-\(Int(ms))-\(Int(glide))-\(gain)-\(noise)"
        let buf = cache[key] ?? make(freq: freq, ms: ms, gain: gain, noise: noise, glide: glide)
        cache[key] = buf
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        idle?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.player.stop(); self?.engine.pause() }
        idle = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    private func make(freq: Double, ms: Double, gain: Float, noise: Float, glide: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(sr * ms / 1000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let out = buf.floatChannelData![0]
        let dur = ms / 1000, decay = 6 / dur
        var phase = 0.0
        for i in 0..<Int(n) {
            let t = Double(i) / sr
            let attack = min(t / 0.0008, 1)
            let env = attack * exp(-t * decay)
            phase += 2 * .pi * (freq + glide * t / dur) / sr
            let click = Float.random(in: -1...1) * noise * Float(exp(-t * decay * 5))
            out[i] = (Float(sin(phase)) * (1 - noise) + click) * Float(env) * gain
        }
        return buf
    }
}
