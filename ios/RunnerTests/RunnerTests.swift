import AVFoundation
import Flutter
import UserNotifications
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testCompletionSoundHasExpectedDuration() throws {
    RestCompletionFeedback.prepareSound()
    let player = try AVAudioPlayer(contentsOf: RestCompletionFeedback.soundURL)
    XCTAssertEqual(player.duration, 2.4, accuracy: 0.02)
  }

  private func schedule(_ timer: RestTimerNotifications, seconds: Int = 90,
                        deadline: Date? = nil, result: @escaping FlutterResult) {
    var arguments: [String: Any] = ["seconds": seconds]
    if let deadline = deadline {
      arguments["endsAtMilliseconds"] = deadline.timeIntervalSince1970 * 1000
    }
    timer.handle(FlutterMethodCall(methodName: "schedule", arguments: arguments), result: result)
  }

  func testCancelWhilePermissionPendingNeverSchedules() {
    let center = FakeNotificationCenter()
    let timer = RestTimerNotifications(center: center)
    let done = expectation(description: "schedule callback")
    schedule(timer) { _ in done.fulfill() }
    timer.handle(FlutterMethodCall(methodName: "cancel", arguments: nil)) { _ in }
    center.permissions.removeFirst()(true, nil)
    wait(for: [done], timeout: 2)
    XCTAssertTrue(center.requests.isEmpty)
  }

  func testOlderPermissionCallbackCannotReplaceNewRest() {
    let center = FakeNotificationCenter()
    let timer = RestTimerNotifications(center: center)
    let old = expectation(description: "old callback")
    let latest = expectation(description: "latest callback")
    schedule(timer, seconds: 90) { _ in old.fulfill() }
    schedule(timer, seconds: 30) { _ in latest.fulfill() }
    center.permissions[1](true, nil)
    center.permissions[0](true, nil)
    wait(for: [old, latest], timeout: 2)
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertNotNil(center.requests[0].content.sound)
    let trigger = center.requests[0].trigger as! UNTimeIntervalNotificationTrigger
    XCTAssertLessThanOrEqual(trigger.timeInterval, 30)
  }

  func testCancelWhileAddPendingRemovesLateRequest() {
    let center = FakeNotificationCenter()
    center.delayAdd = true
    let timer = RestTimerNotifications(center: center)
    let done = expectation(description: "add callback")
    schedule(timer) { _ in done.fulfill() }
    center.permissions[0](true, nil)
    let adding = expectation(description: "add started")
    DispatchQueue.main.async { adding.fulfill() }
    wait(for: [adding], timeout: 2)
    XCTAssertEqual(center.requests.count, 1)
    let id = center.requests[0].identifier
    timer.handle(FlutterMethodCall(methodName: "cancel", arguments: nil)) { _ in }
    center.removed.removeAll()
    center.addCallbacks[0](nil)
    wait(for: [done], timeout: 2)
    XCTAssertTrue(center.removed.contains(id))
  }

  func testPermissionDelayUsesOriginalDeadlineAndSkipsExpiredRest() {
    let center = FakeNotificationCenter()
    let timer = RestTimerNotifications(center: center)
    let first = expectation(description: "shortened notification")
    schedule(timer, seconds: 90, deadline: Date().addingTimeInterval(5)) { _ in first.fulfill() }
    center.permissions[0](true, nil)
    wait(for: [first], timeout: 2)
    XCTAssertEqual(center.requests.count, 1)
    let trigger = center.requests[0].trigger as! UNTimeIntervalNotificationTrigger
    XCTAssertLessThanOrEqual(trigger.timeInterval, 5)
    let second = expectation(description: "expired notification")
    schedule(timer, deadline: Date().addingTimeInterval(-1)) { _ in second.fulfill() }
    center.permissions[1](true, nil)
    wait(for: [second], timeout: 2)
    XCTAssertEqual(center.requests.count, 1)
  }
}

private final class FakeNotificationCenter: RestNotificationCenter {
  var permissions: [(Bool, Error?) -> Void] = []
  var requests: [UNNotificationRequest] = []
  var removed: [String] = []
  var delayAdd = false
  var addCallbacks: [(Error?) -> Void] = []
  func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping (Bool, Error?) -> Void) {
    permissions.append(completionHandler)
  }
  func add(_ request: UNNotificationRequest, withCompletionHandler callback: ((Error?) -> Void)?) {
    requests.append(request)
    if let callback = callback {
      if delayAdd { addCallbacks.append(callback) } else { callback(nil) }
    }
  }
  func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) {
    completionHandler([])
  }
  func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) {
    completionHandler([])
  }
  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    removed.append(contentsOf: identifiers)
  }
  func removeDeliveredNotifications(withIdentifiers: [String]) {}
}
