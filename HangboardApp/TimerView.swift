import SwiftUI
import SwiftData
import Combine
import AVFoundation

private enum WorkoutPhase: Equatable {
    case idle, countdown, hanging, repRest, setRest, done
}

struct TimerView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var hangSeconds = 7
    @State private var repRestSeconds = 180
    @State private var setRestSeconds = 300
    @State private var targetReps = 3
    @State private var targetSets = 2

    @State private var phase: WorkoutPhase = .idle
    @State private var currentSet = 0
    @State private var currentRep = 0
    @State private var secondsRemaining = 0

    @StateObject private var audioPlayer = AudioCuePlayer()

    @State private var showSaveSheet = false
    @State private var showPRCelebration = false
    @State private var completedSets: [(reps: Int, grip: GripType, weight: Double)] = []

    private let clockTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if phase == .idle || phase == .done {
                    configView
                } else {
                    activeView
                }
            }
            .navigationTitle("Timer")
        }
        .onReceive(clockTick) { _ in
            guard phase != .idle && phase != .done else { return }
            secondsRemaining -= 1
            if [.countdown, .repRest, .setRest].contains(phase) && (1...3).contains(secondsRemaining) {
                audioPlayer.playCountdownCue()
            }
            if secondsRemaining <= 0 { advance() }
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveWorkoutSheet(
                sets: targetSets,
                reps: targetReps,
                hangSeconds: hangSeconds,
                repRestSeconds: repRestSeconds,
                setRestSeconds: setRestSeconds,
                onSave: saveWorkout,
                onDiscard: { showSaveSheet = false }
            )
        }
        .fullScreenCover(isPresented: $showPRCelebration) {
            PRCelebrationView { showPRCelebration = false }
        }
    }

    private var configView: some View {
        VStack(spacing: 24) {
            if phase == .done {
                Label("Workout complete!", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.green)

                Button("Log Workout") { showSaveSheet = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Divider()
            }

            VStack(alignment: .leading, spacing: 0) {
                Stepper("Hang: \(hangSeconds)s", value: $hangSeconds, in: 1...60)
                    .padding(.vertical, 12)
                Divider()
                Stepper("Rep rest: \(repRestSeconds / 60)m \(repRestSeconds % 60)s",
                        value: $repRestSeconds, in: 0...600, step: 30)
                    .padding(.vertical, 12)
                Divider()
                Stepper("Set rest: \(setRestSeconds / 60)m \(setRestSeconds % 60)s",
                        value: $setRestSeconds, in: 0...600, step: 30)
                    .padding(.vertical, 12)
                Divider()
                Stepper("Reps: \(targetReps)", value: $targetReps, in: 1...20)
                    .padding(.vertical, 12)
                Divider()
                Stepper("Sets: \(targetSets)", value: $targetSets, in: 1...10)
                    .padding(.vertical, 12)
            }

            Button("Start Workout") { startWorkout() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    private var activeView: some View {
        VStack(spacing: 32) {
            Text(phaseLabel)
                .font(.largeTitle.bold())
                .foregroundStyle(phaseColor)

            Text(formattedTime(secondsRemaining))
                .font(.system(size: 96, weight: .bold, design: .monospaced))
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: secondsRemaining)

            Text(phase == .countdown ? "Get into position" : "Set \(currentSet) of \(targetSets)  ·  Rep \(currentRep) of \(targetReps)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Stop") { phase = .done }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding()
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var phaseLabel: String {
        switch phase {
        case .countdown: "GET READY"
        case .hanging: "HANG"
        case .repRest: "REP REST"
        case .setRest: "SET REST"
        default: ""
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .countdown: .orange
        case .hanging: .red
        case .repRest: .green
        case .setRest: .blue
        default: .primary
        }
    }

    private func startWorkout() {
        currentSet = 1
        currentRep = 1
        phase = .countdown
        secondsRemaining = 10
    }

    private func advance() {
        switch phase {
        case .countdown:
            phase = .hanging
            secondsRemaining = hangSeconds
            audioPlayer.playStartCue()
        case .hanging:
            audioPlayer.playEndCue()
            if currentRep < targetReps {
                currentRep += 1
                phase = .repRest
                secondsRemaining = repRestSeconds
            } else if currentSet < targetSets {
                currentSet += 1
                currentRep = 1
                phase = .setRest
                secondsRemaining = setRestSeconds
            } else {
                phase = .done
            }
        case .repRest, .setRest:
            phase = .hanging
            secondsRemaining = hangSeconds
            audioPlayer.playStartCue()
        default:
            break
        }
    }

    private func saveWorkout(grip: GripType, weight: Double, workoutType: WorkoutType) {
        let allSets = (try? modelContext.fetch(FetchDescriptor<HangSet>())) ?? []
        let previousMax = allSets.map(\.weightAddedLbs).max() ?? 0
        let isPR = weight > 0 && weight > previousMax

        let session = WorkoutSession(date: Date(), workoutType: workoutType)
        for _ in 0..<targetSets {
            let hangSet = HangSet(
                gripType: grip,
                hangTimeSeconds: hangSeconds,
                reps: targetReps,
                setRestSeconds: setRestSeconds,
                repRestSeconds: repRestSeconds,
                weightAddedLbs: weight
            )
            session.sets.append(hangSet)
        }
        modelContext.insert(session)
        showSaveSheet = false
        phase = .idle
        if isPR { showPRCelebration = true }
    }
}

struct SaveWorkoutSheet: View {
    let sets: Int
    let reps: Int
    let hangSeconds: Int
    let repRestSeconds: Int
    let setRestSeconds: Int
    let onSave: (GripType, Double, WorkoutType) -> Void
    let onDiscard: () -> Void

    @State private var weight: Double = 0
    @State private var workoutType: WorkoutType = .maxHang

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout type") {
                    Picker("Type", selection: $workoutType) {
                        ForEach(WorkoutType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Added weight") {
                    HStack {
                        TextField("0", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                        Text("lb")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Summary") {
                    LabeledContent("Sets", value: "\(sets)")
                    LabeledContent("Reps per set", value: "\(reps)")
                    LabeledContent("Hang time", value: "\(hangSeconds)s")
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { onDiscard() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(.halfCrimp, weight, workoutType) }
                }
            }
        }
    }
}

final class AudioCuePlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate = 44100.0

    init() {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func playStartCue()     { playTone(frequency: 880, duration: 0.15) }
    func playEndCue()       { playTone(frequency: 440, duration: 0.25) }
    func playCountdownCue() { playTone(frequency: 620, duration: 0.08) }

    private func playTone(frequency: Double, duration: Double) {
        // .playback + .mixWithOthers: plays through the silent switch and alongside music.
        // Session and engine are set up here (not in init) so they're ready at call time.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        let fadeFrames = Int(Double(frameCount) * 0.2)
        for i in 0..<Int(frameCount) {
            let envelope = i >= Int(frameCount) - fadeFrames
                ? Double(Int(frameCount) - i) / Double(fadeFrames)
                : 1.0
            data[i] = Float(sin(2 * .pi * frequency * Double(i) / sampleRate) * 0.5 * envelope)
        }
        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying { playerNode.play() }
    }
}

struct PRCelebrationView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Text("Hangboard PR!")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.yellow)

                Text("You've got that dog in you!")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)

                Spacer()

                Group {
                    if UIImage(named: "pr_dog") != nil {
                        Image("pr_dog")
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        Text("🐕💪🌕")
                            .font(.system(size: 100))
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                Button("Let's go!") { onDismiss() }
                    .font(.title2.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                    .controlSize(.large)

                    .padding(.bottom, 16)
            }
        }
    }
}

#Preview {
    TimerView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}

#Preview("PR Celebration") {
    PRCelebrationView {}
}
