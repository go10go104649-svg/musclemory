import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct RestTimerAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var startedAt: Date
    var endsAt: Date
    var exerciseName: String
  }
  var timerID: String
}
