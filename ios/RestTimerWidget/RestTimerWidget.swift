import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RestTimerWidgetBundle: WidgetBundle {
  var body: some Widget { RestTimerWidget() }
}

struct RestTimerWidget: Widget {
  private let lime = Color(red: 0.78, green: 0.95, blue: 0.42)
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RestTimerAttributes.self) { context in
      HStack(spacing: 16) {
        Image(systemName: "timer").font(.title).foregroundStyle(lime)
        VStack(alignment: .leading, spacing: 4) {
          Text("MUSCLEMORY").font(.caption.bold())
          Text(context.isStale ? "休憩終了" : "休憩タイマー").font(.headline)
          if !context.state.exerciseName.isEmpty {
            Text(context.state.exerciseName).font(.caption).lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        countdown(context).font(.title.bold()).frame(maxWidth: 110)
      }
      .padding(16)
      .activityBackgroundTint(Color(red: 0.06, green: 0.09, blue: 0.12))
      .activitySystemActionForegroundColor(.white)
      .foregroundStyle(.white)
      .widgetURL(URL(string: "musclemory://rest-timer/"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "timer").foregroundStyle(lime)
        }
        DynamicIslandExpandedRegion(.trailing) {
          countdown(context).monospacedDigit().frame(width: 75)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 3) {
            Text("MUSCLEMORY · \(context.isStale ? "休憩終了" : "休憩タイマー")").font(.headline)
            Text(context.state.exerciseName).font(.caption).lineLimit(1)
          }
        }
      } compactLeading: {
        Image(systemName: "timer").foregroundStyle(lime)
      } compactTrailing: {
        countdown(context).frame(width: 54)
      } minimal: {
        Image(systemName: "timer").foregroundStyle(lime)
      }
      .widgetURL(URL(string: "musclemory://rest-timer/"))
      .keylineTint(lime)
    }
  }

  @ViewBuilder
  private func countdown(_ context: ActivityViewContext<RestTimerAttributes>) -> some View {
    if context.isStale {
      Text("00:00").monospacedDigit()
    } else {
      Text(timerInterval: context.state.startedAt...context.state.endsAt,
           countsDown: true, showsHours: false).monospacedDigit()
    }
  }
}
