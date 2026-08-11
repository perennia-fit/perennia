import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UNUserNotificationCenterDelegate
{
  private let timerBackgroundChannelName = "open_workout_logger/timer_background"
  private var timerBackgroundChannel: FlutterMethodChannel?

  // a cold-start tap arrives before Flutter registers its callback.
  // Buffer the payload until `timerNotificationsReady` drains it.
  private var flutterReady = false
  private var bufferedTapPayload: [String: Any?]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Must be set BEFORE any notification is scheduled/delivered so taps and
    // foreground presentation route through us.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard
      let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TimerBackgroundChannel")
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: timerBackgroundChannelName,
      binaryMessenger: registrar.messenger()
    )
    timerBackgroundChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleTimerBackgroundCall(call, result: result)
    }
  }

  private func handleTimerBackgroundCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "requestNotificationPermissionIfNeeded":
      requestNotificationPermission(result: result)
    case "scheduleTimer":
      scheduleTimer(call: call, result: result)
    case "cancelTimer":
      cancelTimer(call: call, result: result)
    case "timerNotificationsReady":
      flutterReady = true
      drainBufferedTap()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      if self.isNotificationAuthorized(settings.authorizationStatus) {
        self.complete(result, with: "granted")
        return
      }
      guard settings.authorizationStatus == .notDetermined else {
        self.complete(result, with: "denied")
        return
      }

      center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        self.complete(result, with: granted ? "granted" : "denied")
      }
    }
  }

  private func scheduleTimer(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let timerId = arguments["timerId"] as? String,
      let deadlineAtMillis = arguments["deadlineAtMillis"] as? NSNumber,
      let title = arguments["title"] as? String,
      let body = arguments["body"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_timer_schedule",
          message: "Timer schedule payload is missing required fields.",
          details: nil
        )
      )
      return
    }

    let soundEnabled = (arguments["soundEnabled"] as? Bool) ?? true
    let countdownLabel = (arguments["countdownLabel"] as? String) ?? ""
    let userInfo: [String: Any] = [
      "timerId": timerId,
      "workoutId": arguments["workoutId"] as? String as Any,
      "workoutExerciseId": arguments["workoutExerciseId"] as? String as Any,
    ]

    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard self.isNotificationAuthorized(settings.authorizationStatus) else {
        self.complete(result, with: "denied")
        return
      }

      let deadline = Date(timeIntervalSince1970: deadlineAtMillis.doubleValue / 1000.0)
      let interval = max(1.0, deadline.timeIntervalSinceNow)

      // Completion request at the deadline.
      let completion = UNMutableNotificationContent()
      completion.title = title
      completion.body = body
      completion.sound = soundEnabled
        ? UNNotificationSound(named: UNNotificationSoundName("TimerComplete.caf"))
        : nil
      completion.userInfo = userInfo
      let completionRequest = UNNotificationRequest(
        identifier: timerId,
        content: completion,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
      )

      // prepare request 3s before the deadline (never earlier than 1s
      // from now). Scheduled alongside completion; cancelled together.
      let prepareInterval = max(1.0, interval - 3.0)
      let prepare = UNMutableNotificationContent()
      prepare.title = title
      prepare.body = "\(countdownLabel) 0:03"
      prepare.sound = soundEnabled
        ? UNNotificationSound(named: UNNotificationSoundName("PrepareBeep.caf"))
        : nil
      prepare.userInfo = userInfo
      let prepareRequest = UNNotificationRequest(
        identifier: self.prepareIdentifier(timerId),
        content: prepare,
        trigger: UNTimeIntervalNotificationTrigger(
          timeInterval: prepareInterval, repeats: false)
      )

      center.removePendingNotificationRequests(withIdentifiers: [
        timerId, self.prepareIdentifier(timerId),
      ])

      let group = DispatchGroup()
      var scheduleError: Error?
      for request in [prepareRequest, completionRequest] {
        group.enter()
        center.add(request) { error in
          if let error, scheduleError == nil { scheduleError = error }
          group.leave()
        }
      }
      group.notify(queue: .main) {
        if let scheduleError {
          self.complete(
            result,
            with: FlutterError(
              code: "timer_schedule_failed",
              message: scheduleError.localizedDescription,
              details: nil
            )
          )
          return
        }
        self.complete(result, with: "granted")
      }
    }
  }

  private func cancelTimer(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let timerId = arguments["timerId"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_timer_cancel",
          message: "Timer cancel payload is missing timerId.",
          details: nil
        )
      )
      return
    }

    let center = UNUserNotificationCenter.current()
    let ids = [timerId, prepareIdentifier(timerId)]
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
    result(nil)
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Foreground: show a banner only. The in-app cue already covers sound, so
    // passing [.sound] here would double the audio.
    completionHandler([.banner])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let payload: [String: Any?] = [
      "timerId": userInfo["timerId"] as? String,
      "workoutId": userInfo["workoutId"] as? String,
      "workoutExerciseId": userInfo["workoutExerciseId"] as? String,
    ]
    forwardTap(payload)
    completionHandler()
  }

  private func forwardTap(_ payload: [String: Any?]) {
    if flutterReady {
      timerBackgroundChannel?.invokeMethod("onTimerNotificationTapped", arguments: payload)
    } else {
      bufferedTapPayload = payload
    }
  }

  private func drainBufferedTap() {
    guard let payload = bufferedTapPayload else { return }
    bufferedTapPayload = nil
    timerBackgroundChannel?.invokeMethod("onTimerNotificationTapped", arguments: payload)
  }

  private func prepareIdentifier(_ timerId: String) -> String {
    return "prepare:\(timerId)"
  }

  private func isNotificationAuthorized(_ status: UNAuthorizationStatus) -> Bool {
    if status == .authorized || status == .provisional {
      return true
    }
    if #available(iOS 14.0, *), status == .ephemeral {
      return true
    }
    return false
  }

  private func complete(_ result: @escaping FlutterResult, with value: Any?) {
    DispatchQueue.main.async {
      result(value)
    }
  }
}
