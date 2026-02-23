import Foundation
import Speech
import AVFoundation
import Observation

@MainActor @Observable
final class SpeechManager {
    var isRecording = false
    var transcript = ""
    var isAvailable = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isTapInstalled = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
#if targetEnvironment(simulator)
        isAvailable = false
        transcript = "Voice input is unavailable in iOS Simulator. Use typed input or run on a real iPhone."
#endif
    }

    func requestPermission() {
#if targetEnvironment(simulator)
        isAvailable = false
        if transcript.isEmpty {
            transcript = "Voice input is unavailable in iOS Simulator."
        }
        return
#else
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.isAvailable = (status == .authorized) && (self?.recognizer?.isAvailable ?? false)
            }
        }
#endif
    }

    func startRecording() {
#if targetEnvironment(simulator)
        transcript = "Voice input is unavailable in iOS Simulator."
        isRecording = false
        return
#else
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        stopRecording()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            transcript = "Voice setup failed: \(error.localizedDescription)"
            isRecording = false
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.inputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            transcript = "Voice input unavailable on current audio route."
            isRecording = false
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        isTapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self?.stopRecording()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            transcript = "Voice start failed: \(error.localizedDescription)"
            stopRecording()
            isRecording = false
        }
#endif
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}
