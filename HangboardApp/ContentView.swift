import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TimerView()
                .tabItem { Label("Timer", systemImage: "timer") }
            WorkoutHistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
            InjuryTrackerView()
                .tabItem { Label("Injuries", systemImage: "cross.case.fill") }
            ProgressChartView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
        }
    }
}
