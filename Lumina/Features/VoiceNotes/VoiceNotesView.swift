import SwiftUI
import AVFoundation
import Speech

struct VoiceNotesView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var recordingURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Voice Notes to Coach")
                    .font(.largeTitle.bold())
                    .padding(.horizontal)

                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Talk to your coach")
                            .font(.headline)

                        Text("Record how you're feeling, what you're struggling with, or a quick win. The AI will listen and respond with personalized support.")
                            .foregroundStyle(.white.opacity(0.85))

                        Button {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        } label: {
                            HStack {
                                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    .font(.largeTitle)
                                Text(isRecording ? "Stop Recording" : "Record Voice Note")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if !transcribedText.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What you said:")
                                .font(.headline)

                            Text(transcribedText)
                                .foregroundStyle(.white.opacity(0.9))

                            Button("Send to Coach") {
                                sendToCoach()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How this helps the coach")
                            .font(.headline)
                        Text("Voice notes give the coach much richer emotional and contextual data than structured check-ins alone. Over time this makes its advice significantly more personalized.")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .glassBackground()
        .navigationTitle("Voice Notes")
        .onAppear {
            requestMicrophonePermission()
        }
    }

    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_note.m4a")
            recordingURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
            transcribedText = ""
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false

        guard let url = recordingURL else { return }

        // Transcribe
        let recognizer = SFSpeechRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: url)

        recognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                transcribedText = result.bestTranscription.formattedString
            } else if let error = error {
                errorMessage = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    private func sendToCoach() {
        guard !transcribedText.isEmpty else { return }

        // Rich memory entry
        viewModel.saveCoachMemoryEntry(type: .reflection, content: "Voice note from user: \(transcribedText)")

        // Send as a pending message that RealAIChatView will pick up and respond to
        viewModel.pendingVoiceMessage = transcribedText
        
        transcribedText = ""
        
        // Show helpful guidance
        // In a full app this would deep-link to the Coach tab
    }
}