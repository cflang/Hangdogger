import SwiftUI
import SwiftData
import Charts

private struct RepeaterPoint: Identifiable {
    let date: Date
    let weight: Double
    let sets: Int
    var id: String { "\(date.timeIntervalSince1970)-\(sets)" }
}

private enum ChartTimeRange: String, CaseIterable {
    case threeMonths = "3M"
    case sixMonths   = "6M"
    case oneYear     = "1Y"
    case allTime     = "All"

    func cutoffDate() -> Date? {
        let cal = Calendar.current
        switch self {
        case .threeMonths: return cal.date(byAdding: .month, value: -3,  to: Date())
        case .sixMonths:   return cal.date(byAdding: .month, value: -6,  to: Date())
        case .oneYear:     return cal.date(byAdding: .year,  value: -1,  to: Date())
        case .allTime:     return nil
        }
    }
}

private let shortDate = Date.FormatStyle()
    .month(.defaultDigits).day(.defaultDigits).year(.twoDigits)

struct ProgressChartView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \FingerInjury.onsetDate) private var injuries: [FingerInjury]

    @State private var selectedWorkoutType: WorkoutType = .maxHang
    @State private var selectedRange: ChartTimeRange = .allTime

    // MARK: – filtered data

    private var cutoff: Date? { selectedRange.cutoffDate() }

    private var maxHangPoints: [(date: Date, weight: Double)] {
        sessions.compactMap { session in
            guard session.workoutType == .maxHang else { return nil }
            if let c = cutoff, session.date < c { return nil }
            guard let max = session.sets.map(\.weightAddedLbs).max() else { return nil }
            return (date: session.date, weight: max)
        }
    }

    private var repeaterPoints: [RepeaterPoint] {
        sessions.compactMap { session in
            guard session.workoutType == .repeaters else { return nil }
            if let c = cutoff, session.date < c { return nil }
            guard let maxWeight = session.sets.map(\.weightAddedLbs).max() else { return nil }
            return RepeaterPoint(date: session.date, weight: maxWeight, sets: session.sets.count)
        }
    }

    private var visibleInjuries: [FingerInjury] {
        let rangeStart = cutoff ?? Date.distantPast
        let today = Date()
        return injuries.filter { injury in
            let end = injury.resolutionDate ?? today
            return end >= rangeStart && injury.onsetDate <= today
        }
    }

    private var xDomainStart: Date {
        cutoff ?? {
            let dates = sessions.map(\.date) + injuries.map(\.onsetDate)
            return dates.min() ?? Date()
        }()
    }

    // MARK: – body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Workout type", selection: $selectedWorkoutType) {
                    ForEach(WorkoutType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                Picker("Range", selection: $selectedRange) {
                    ForEach(ChartTimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if selectedWorkoutType == .maxHang {
                    maxHangChart
                } else {
                    repeaterChart
                }
            }
            .navigationTitle("Progress")
        }
    }

    // MARK: – charts

    @ViewBuilder
    private var maxHangChart: some View {
        if maxHangPoints.isEmpty {
            ContentUnavailableView(
                "No Data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("No Max Hang sessions in this range.")
            )
        } else {
            Chart {
                injuryOverlays
                ForEach(maxHangPoints, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight (lb)", point.weight)
                    )
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight (lb)", point.weight)
                    )
                }
            }
            .chartXScale(domain: xDomainStart...Date())
            .chartXAxis {
                AxisMarks { AxisGridLine(); AxisTick(); AxisValueLabel(format: shortDate) }
            }
            .chartYAxisLabel("Added weight (lb)")
            .padding()
        }
    }

    @ViewBuilder
    private var repeaterChart: some View {
        if repeaterPoints.isEmpty {
            ContentUnavailableView(
                "No Data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("No 7:3 Repeaters sessions in this range.")
            )
        } else {
            Chart {
                injuryOverlays
                ForEach(repeaterPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight (lb)", point.weight)
                    )
                    .foregroundStyle(by: .value("Sets", "\(point.sets) sets"))
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight (lb)", point.weight)
                    )
                    .foregroundStyle(by: .value("Sets", "\(point.sets) sets"))
                }
            }
            .chartXScale(domain: xDomainStart...Date())
            .chartXAxis {
                AxisMarks { AxisGridLine(); AxisTick(); AxisValueLabel(format: shortDate) }
            }
            .chartYAxisLabel("Added weight (lb)")
            .padding()
        }
    }

    @ChartContentBuilder
    private var injuryOverlays: some ChartContent {
        ForEach(visibleInjuries) { injury in
            RectangleMark(
                xStart: .value("Onset", injury.onsetDate),
                xEnd: .value("End", injury.resolutionDate ?? Date())
            )
            .foregroundStyle(.red.opacity(0.12))
            .annotation(position: .top, alignment: .leading) {
                Text(injury.injuryType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 2)
            }
        }
    }
}

#Preview {
    ProgressChartView()
        .modelContainer(for: [WorkoutSession.self, FingerInjury.self], inMemory: true)
}
