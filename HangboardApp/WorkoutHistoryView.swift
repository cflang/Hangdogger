import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showLogSheet = false
    @State private var showPRCelebration = false
    @State private var sessionToEdit: WorkoutSession? = nil
    @State private var showImportPicker = false
    @State private var showImportAlert = false
    @State private var importAlertMessage = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    Button { sessionToEdit = session } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.date, format: .dateTime.month(.wide).day().year())
                                .font(.headline)
                            Text(sessionSummary(session))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSessions)
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showLogSheet = true } label: {
                            Label("Log Workout", systemImage: "plus")
                        }
                        Divider()
                        ShareLink(
                            item: makeTemplateURL(),
                            preview: SharePreview("hangboard_template.csv",
                                                  icon: Image(systemName: "doc.badge.arrow.down"))
                        ) {
                            Label("Download CSV Template", systemImage: "doc.badge.arrow.down")
                        }
                        Button { showImportPicker = true } label: {
                            Label("Import CSV", systemImage: "square.and.arrow.down")
                        }
                        ShareLink(
                            item: makeExportURL(),
                            preview: SharePreview("hangboard_workouts.csv",
                                                  icon: Image(systemName: "doc.text"))
                        ) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            ManualLogSheet { session in
                let allSets = (try? modelContext.fetch(FetchDescriptor<HangSet>())) ?? []
                let previousMax = allSets.map(\.weightAddedLbs).max() ?? 0
                let newMax = session.sets.map(\.weightAddedLbs).max() ?? 0
                let isPR = newMax > 0 && newMax > previousMax

                modelContext.insert(session)
                showLogSheet = false
                if isPR { showPRCelebration = true }
            } onDiscard: {
                showLogSheet = false
            }
        }
        .sheet(item: $sessionToEdit) { session in
            EditWorkoutSheet(session: session) { sessionToEdit = nil }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first,
                      url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let csv = try String(contentsOf: url, encoding: .utf8)
                    let count = try CSVManager.importCSV(csv, context: modelContext)
                    importAlertMessage = count > 0
                        ? "Imported \(count) workout\(count == 1 ? "" : "s")."
                        : "No new workouts found — duplicates are skipped."
                } catch {
                    importAlertMessage = "Import failed: \(error.localizedDescription)"
                }
            case .failure(let error):
                importAlertMessage = "Could not open file: \(error.localizedDescription)"
            }
            showImportAlert = true
        }
        .alert("Import Result", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importAlertMessage)
        }
        .fullScreenCover(isPresented: $showPRCelebration) {
            PRCelebrationView { showPRCelebration = false }
        }
    }

    private func makeExportURL() -> URL {
        let csv = CSVManager.export(sessions: Array(sessions))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hangboard_workouts.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTemplateURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hangboard_template.csv")
        try? CSVManager.templateCSV().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func sessionSummary(_ session: WorkoutSession) -> String {
        guard !session.sets.isEmpty else { return "No sets recorded" }
        let maxWeight = session.sets.map(\.weightAddedLbs).max() ?? 0
        let totalSets = session.sets.count
        return "\(totalSets) set\(totalSets == 1 ? "" : "s") · \(session.workoutType.rawValue) · +\(maxWeight.formatted())lb"
    }

    private func deleteSessions(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sessions[index])
        }
    }
}

struct ManualLogSheet: View {
    let onSave: (WorkoutSession) -> Void
    let onDiscard: () -> Void

    @State private var date = Date()
    @State private var workoutType: WorkoutType = .maxHang
    @State private var sets = 2
    @State private var reps = 3
    @State private var hangSeconds = 7
    @State private var weight: Double = 0
    @State private var setRestSeconds = 300
    @State private var repRestSeconds = 180

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $workoutType) {
                        ForEach(WorkoutType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Sets & Reps") {
                    Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps per set: \(reps)", value: $reps, in: 1...20)
                    Stepper("Hang time: \(hangSeconds)s", value: $hangSeconds, in: 1...60)
                }

                Section("Weight & Rest") {
                    HStack {
                        Text("Added weight")
                        Spacer()
                        TextField("0", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("lb")
                            .foregroundStyle(.secondary)
                    }
                    Stepper("Set rest: \(setRestSeconds / 60)m \(setRestSeconds % 60)s",
                            value: $setRestSeconds, in: 0...600, step: 30)
                    Stepper("Rep rest: \(repRestSeconds / 60)m \(repRestSeconds % 60)s",
                            value: $repRestSeconds, in: 0...600, step: 30)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { onDiscard() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(buildSession()) }
                }
            }
        }
    }

    private func buildSession() -> WorkoutSession {
        let session = WorkoutSession(date: date, workoutType: workoutType)
        for _ in 0..<sets {
            session.sets.append(HangSet(
                gripType: .halfCrimp,
                hangTimeSeconds: hangSeconds,
                reps: reps,
                setRestSeconds: setRestSeconds,
                repRestSeconds: repRestSeconds,
                weightAddedLbs: weight
            ))
        }
        return session
    }
}

struct EditWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    let session: WorkoutSession
    let onDismiss: () -> Void

    @State private var date: Date
    @State private var workoutType: WorkoutType
    @State private var sets: Int
    @State private var reps: Int
    @State private var hangSeconds: Int
    @State private var weight: Double
    @State private var setRestSeconds: Int
    @State private var repRestSeconds: Int

    init(session: WorkoutSession, onDismiss: @escaping () -> Void) {
        self.session = session
        self.onDismiss = onDismiss
        let first = session.sets.first
        _date = State(initialValue: session.date)
        _workoutType = State(initialValue: session.workoutType)
        _sets = State(initialValue: max(session.sets.count, 1))
        _reps = State(initialValue: first?.reps ?? 3)
        _hangSeconds = State(initialValue: first?.hangTimeSeconds ?? 7)
        _weight = State(initialValue: first?.weightAddedLbs ?? 0)
        _setRestSeconds = State(initialValue: (first?.setRestSeconds ?? nil) ?? 300)
        _repRestSeconds = State(initialValue: (first?.repRestSeconds ?? nil) ?? 180)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $workoutType) {
                        ForEach(WorkoutType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Sets & Reps") {
                    Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps per set: \(reps)", value: $reps, in: 1...20)
                    Stepper("Hang time: \(hangSeconds)s", value: $hangSeconds, in: 1...60)
                }

                Section("Weight & Rest") {
                    HStack {
                        Text("Added weight")
                        Spacer()
                        TextField("0", value: $weight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("lb")
                            .foregroundStyle(.secondary)
                    }
                    Stepper("Set rest: \(setRestSeconds / 60)m \(setRestSeconds % 60)s",
                            value: $setRestSeconds, in: 0...600, step: 30)
                    Stepper("Rep rest: \(repRestSeconds / 60)m \(repRestSeconds % 60)s",
                            value: $repRestSeconds, in: 0...600, step: 30)
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
            }
        }
    }

    private func saveChanges() {
        session.date = date
        session.workoutType = workoutType
        for set in session.sets { modelContext.delete(set) }
        session.sets = []
        for _ in 0..<sets {
            session.sets.append(HangSet(
                gripType: .halfCrimp,
                hangTimeSeconds: hangSeconds,
                reps: reps,
                setRestSeconds: setRestSeconds,
                repRestSeconds: repRestSeconds,
                weightAddedLbs: weight
            ))
        }
        onDismiss()
    }
}

struct CSVImportFormatError: LocalizedError {
    var errorDescription: String? {
        """
        No workouts could be imported — check your file matches this format:

        date,workout_type,sets,reps_per_set,hang_seconds,weight_lbs,set_rest_seconds,rep_rest_seconds
        2025-10-13,Max Hang,2,3,7,53.0,300,180

        • date — YYYY-MM-DD
        • workout_type — "Max Hang" or "7:3 Repeaters"
        • sets / reps_per_set / hang_seconds — whole numbers
        • weight_lbs — decimal (e.g. 53.0)
        • set_rest_seconds / rep_rest_seconds — whole numbers, may be left empty

        Download the CSV template from the ••• menu for a ready-to-fill example.
        """
    }
}

struct CSVManager {
    static let csvHeader = "date,workout_type,sets,reps_per_set,hang_seconds,weight_lbs,set_rest_seconds,rep_rest_seconds"

    static func templateCSV() -> String {
        """
        \(csvHeader)
        2025-10-13,Max Hang,2,3,7,53.0,300,180
        2025-11-01,7:3 Repeaters,4,6,7,20.0,300,180
        """
    }

    static func export(sessions: [WorkoutSession]) -> String {
        var lines = [csvHeader]
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        for session in sessions.sorted(by: { $0.date < $1.date }) {
            guard let first = session.sets.first else { continue }
            let row = [
                df.string(from: session.date),
                session.workoutType.rawValue,
                String(session.sets.count),
                String(first.reps),
                String(first.hangTimeSeconds),
                String(first.weightAddedLbs),
                first.setRestSeconds.map(String.init) ?? "",
                first.repRestSeconds.map(String.init) ?? ""
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    static func importCSV(_ text: String, context: ModelContext) throws -> Int {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return 0 }

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        let cal = Calendar.current

        let existing = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var existingDays = Set(existing.map { cal.startOfDay(for: $0.date) })

        var imported = 0
        var malformed = 0
        for line in lines.dropFirst() {
            let f = line.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 6,
                  let date = df.date(from: f[0]),
                  let workoutType = WorkoutType(rawValue: f[1]),
                  let sets = Int(f[2]),
                  let reps = Int(f[3]),
                  let hangSec = Int(f[4]),
                  let weight = Double(f[5]) else { malformed += 1; continue }

            let day = cal.startOfDay(for: date)
            guard !existingDays.contains(day) else { continue }

            let setRest = f.count > 6 && !f[6].isEmpty ? Int(f[6]) : nil
            let repRest = f.count > 7 && !f[7].isEmpty ? Int(f[7]) : nil

            let session = WorkoutSession(date: date, workoutType: workoutType)
            for _ in 0..<sets {
                session.sets.append(HangSet(
                    gripType: .halfCrimp,
                    hangTimeSeconds: hangSec,
                    reps: reps,
                    setRestSeconds: setRest,
                    repRestSeconds: repRest,
                    weightAddedLbs: weight
                ))
            }
            context.insert(session)
            existingDays.insert(day)
            imported += 1
        }
        if imported == 0 && malformed > 0 { throw CSVImportFormatError() }
        try context.save()
        return imported
    }
}

#Preview {
    WorkoutHistoryView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
