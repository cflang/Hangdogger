import SwiftUI
import SwiftData

extension InjurySeverity {
    var color: Color {
        switch self {
        case .mild:     .yellow
        case .moderate: .orange
        case .severe:   .red
        }
    }
}

struct InjuryTrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FingerInjury.onsetDate, order: .reverse) private var injuries: [FingerInjury]

    @State private var showAddSheet = false
    @State private var injuryToEdit: FingerInjury? = nil

    private var active: [FingerInjury] { injuries.filter { $0.resolutionDate == nil } }
    private var healed: [FingerInjury] { injuries.filter { $0.resolutionDate != nil } }

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section("Active") {
                        ForEach(active) { injury in
                            Button { injuryToEdit = injury } label: {
                                InjuryRow(injury: injury)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in delete(offsets, from: active) }
                    }
                }
                if !healed.isEmpty {
                    Section("Healed") {
                        ForEach(healed) { injury in
                            Button { injuryToEdit = injury } label: {
                                InjuryRow(injury: injury)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in delete(offsets, from: healed) }
                    }
                }
            }
            .navigationTitle("Injuries")
            .overlay {
                if injuries.isEmpty {
                    ContentUnavailableView(
                        "No Injuries Logged",
                        systemImage: "cross.case",
                        description: Text("Tap + to record an injury.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Label("Add Injury", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            InjuryFormSheet(injury: nil) { newInjury in
                modelContext.insert(newInjury)
                showAddSheet = false
            } onDiscard: {
                showAddSheet = false
            }
        }
        .sheet(item: $injuryToEdit) { injury in
            InjuryFormSheet(injury: injury) { _ in
                injuryToEdit = nil
            } onDiscard: {
                injuryToEdit = nil
            }
        }
    }

    private func delete(_ offsets: IndexSet, from source: [FingerInjury]) {
        for i in offsets { modelContext.delete(source[i]) }
    }
}

struct InjuryRow: View {
    let injury: FingerInjury

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(injury.hand.rawValue) \(injury.finger.rawValue)")
                    .font(.headline)
                Spacer()
                Text(injury.severity.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(injury.severity.color.opacity(0.15))
                    .foregroundStyle(injury.severity.color)
                    .clipShape(Capsule())
            }
            Text(injury.injuryType.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(durationLabel(injury))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func durationLabel(_ injury: FingerInjury) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        let cal = Calendar.current
        let end = injury.resolutionDate ?? Date()
        let days = cal.dateComponents([.day], from: injury.onsetDate, to: end).day ?? 0
        if let res = injury.resolutionDate {
            return "\(fmt.string(from: injury.onsetDate)) → \(fmt.string(from: res)) · \(days)d"
        } else {
            return "Since \(fmt.string(from: injury.onsetDate)) · \(days)d ongoing"
        }
    }
}

struct InjuryFormSheet: View {
    let injury: FingerInjury?
    let onSave: (FingerInjury) -> Void
    let onDiscard: () -> Void

    @State private var hand: HandSide
    @State private var finger: FingerName
    @State private var injuryType: InjuryType
    @State private var severity: InjurySeverity
    @State private var onsetDate: Date
    @State private var isHealed: Bool
    @State private var resolutionDate: Date
    @State private var notes: String

    init(injury: FingerInjury?, onSave: @escaping (FingerInjury) -> Void, onDiscard: @escaping () -> Void) {
        self.injury = injury
        self.onSave = onSave
        self.onDiscard = onDiscard
        _hand          = State(initialValue: injury?.hand ?? .right)
        _finger        = State(initialValue: injury?.finger ?? .ring)
        _injuryType    = State(initialValue: injury?.injuryType ?? .a2Pulley)
        _severity      = State(initialValue: injury?.severity ?? .mild)
        _onsetDate     = State(initialValue: injury?.onsetDate ?? Date())
        _isHealed      = State(initialValue: injury?.resolutionDate != nil)
        _resolutionDate = State(initialValue: injury?.resolutionDate ?? Date())
        _notes         = State(initialValue: injury?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    Picker("Hand", selection: $hand) {
                        ForEach(HandSide.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Finger", selection: $finger) {
                        ForEach(FingerName.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Injury") {
                    Picker("Type", selection: $injuryType) {
                        ForEach(InjuryType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Severity", selection: $severity) {
                        ForEach(InjurySeverity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Dates") {
                    DatePicker("Onset", selection: $onsetDate, displayedComponents: .date)
                    Toggle("Healed", isOn: $isHealed)
                    if isHealed {
                        DatePicker("Recovery", selection: $resolutionDate,
                                   in: onsetDate..., displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(injury == nil ? "Log Injury" : "Edit Injury")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDiscard() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let target = injury ?? FingerInjury(
            onsetDate: onsetDate,
            hand: hand,
            finger: finger,
            injuryType: injuryType,
            severity: severity
        )
        target.onsetDate       = onsetDate
        target.resolutionDate  = isHealed ? resolutionDate : nil
        target.hand            = hand
        target.finger          = finger
        target.injuryType      = injuryType
        target.severity        = severity
        target.notes           = notes
        onSave(target)
    }
}

#Preview {
    InjuryTrackerView()
        .modelContainer(for: FingerInjury.self, inMemory: true)
}
