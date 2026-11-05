import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UNUserNotificationCenterDelegate
{
  private let timerBackgroundChannelName = "perennia/timer_background"
  private var timerBackgroundChannel: FlutterMethodChannel?
  private let backupExport = BackupExportChannel()
  private let cueSounds = TimerCueSounds()

  // Whether a rest strip on the current route is playing the cues in the app.
  // `willPresent` runs only while the app is in the foreground, so this alone
  // decides whether a timer notification presents.
  private var inAppCuesActive = false

  // The rests whose schedule Dart has cancelled and not scheduled again. Removing
  // a request does not stop one the system has already fired, or one still on its
  // way to `center.add`, and by then `inAppCuesActive` can be false: without this,
  // an end the strip already played would also present a banner and its sound.
  // Read and written only on the main thread. One short id per rest, for the life
  // of the process.
  private var cancelledTimerIds = Set<String>()

  // a cold-start tap arrives before Flutter registers its callback.
  // Buffer the payload until `timerNotificationsReady` drains it.
  private var flutterReady = false
  private var bufferedTapPayload: [String: Any?]?
  // A Supplement reminder tap's local date, buffered the same way.
  private var bufferedReminderDate: String?

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
    // A value left from an engine that died must never silence later rests.
    inAppCuesActive = false
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let backupRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "BackupExportChannel")
    {
      FlutterMethodChannel(
        name: BackupExportChannel.name,
        binaryMessenger: backupRegistrar.messenger()
      ).setMethodCallHandler { [weak self] call, result in
        self?.backupExport.handle(call, result: result)
      }
    }
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
    case "notificationPermissionStatus":
      notificationPermissionStatus(result: result)
    case "scheduleTimer":
      scheduleTimer(call: call, result: result)
    case "cancelTimer":
      cancelTimer(call: call, result: result)
    case "prepareCues":
      cueSounds.prepare()
      result(nil)
    case "playCue":
      let arguments = call.arguments as? [String: Any]
      if let cue = arguments?["cue"] as? String {
        let volume = (arguments?["volume"] as? NSNumber)?.floatValue ?? 1.0
        cueSounds.play(cue: cue, volume: volume)
      }
      result(nil)
    case "setInAppTimerCues":
      let arguments = call.arguments as? [String: Any]
      inAppCuesActive = (arguments?["active"] as? Bool) ?? false
      result(nil)
    case "pendingProtocolReminders":
      pendingProtocolReminders(result: result)
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

  // Read-only: reports the permission without ever prompting.
  private func notificationPermissionStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      if self.isNotificationAuthorized(settings.authorizationStatus) {
        self.complete(result, with: "granted")
      } else if settings.authorizationStatus == .notDetermined {
        self.complete(result, with: "notDetermined")
      } else {
        self.complete(result, with: "denied")
      }
    }
  }

  private func scheduleTimer(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let timerId = arguments["timerId"] as? String,
      let deadlineAtMillis = arguments["deadlineAtMillis"] as? NSNumber,
      let title = arguments["title"] as? String,
      let body = arguments["body"] as? String,
      let prepareText = arguments["prepareText"] as? String
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

    cancelledTimerIds.remove(timerId)

    let soundEnabled = (arguments["soundEnabled"] as? Bool) ?? true
    let getReadyText = arguments["getReadyText"] as? String
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
      let remaining = deadline.timeIntervalSinceNow

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
        trigger: UNTimeIntervalNotificationTrigger(
          timeInterval: max(1.0, remaining), repeats: false)
      )

      // A cue before the deadline, scheduled alongside completion and cancelled
      // together. One less than 0.5 s away is not added: its moment has passed,
      // and firing it late would play a stale cue.
      func cueRequest(
        identifier: String, leadTime: TimeInterval, text: String, sound: String
      ) -> UNNotificationRequest? {
        let interval = remaining - leadTime
        guard interval >= 0.5 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        content.sound = soundEnabled
          ? UNNotificationSound(named: UNNotificationSoundName(sound))
          : nil
        content.userInfo = userInfo
        return UNNotificationRequest(
          identifier: identifier,
          content: content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
      }

      var requests = [completionRequest]
      if let prepareRequest = cueRequest(
        identifier: self.prepareIdentifier(timerId),
        leadTime: 3.0,
        text: prepareText,
        sound: "PrepareBeep.caf"
      ) {
        requests.append(prepareRequest)
      }
      if let getReadyText,
        let getReadyRequest = cueRequest(
          identifier: self.getReadyIdentifier(timerId),
          leadTime: 10.0,
          text: getReadyText,
          sound: "GetReady.caf"
        )
      {
        requests.append(getReadyRequest)
      }

      center.removePendingNotificationRequests(withIdentifiers: [
        timerId, self.prepareIdentifier(timerId), self.getReadyIdentifier(timerId),
      ])

      let group = DispatchGroup()
      var scheduleError: Error?
      for request in requests {
        group.enter()
        center.add(request) { error in
          if let error, scheduleError == nil { scheduleError = error }
          group.leave()
        }
      }
      group.notify(queue: .main) {
        // Cancelled while these were on their way: the cancel's removal found
        // nothing, so they would still fire, even in the background.
        if self.cancelledTimerIds.contains(timerId) {
          center.removePendingNotificationRequests(withIdentifiers: [
            timerId, self.prepareIdentifier(timerId), self.getReadyIdentifier(timerId),
          ])
        }
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

    cancelledTimerIds.insert(timerId)

    let center = UNUserNotificationCenter.current()
    let ids = [timerId, prepareIdentifier(timerId), getReadyIdentifier(timerId)]
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
    result(nil)
  }

  // The Supplement reminders still pending, as `{id, payload}`. Read here,
  // not through flutter_local_notifications' own list, which also reports the
  // rest timer's requests with no id and fails on them. Only a request the
  // plugin scheduled carries its `NotificationId` and `payload` keys.
  private func pendingProtocolReminders(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let reminders = requests.compactMap { request -> [String: Any]? in
        let userInfo = request.content.userInfo
        guard
          let id = userInfo["NotificationId"] as? NSNumber,
          let payload = userInfo["payload"] as? String
        else {
          return nil
        }
        return ["id": id, "payload": payload]
      }
      self.complete(result, with: reminders)
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // A Supplement reminder shows as a banner and stays in the list.
    // A rest timer's cue has exactly one player: nothing here while a strip on
    // the current route plays it in the app or after its rest was cancelled, else
    // this notification's banner and sound (on another screen of the app, the only
    // cue left).
    // `.banner` and `.list` need iOS 14; iOS 13 shows both as an alert.
    let userInfo = notification.request.content.userInfo
    if protocolReminderDate(userInfo) != nil {
      if #available(iOS 14.0, *) {
        completionHandler([.banner, .list])
      } else {
        completionHandler([.alert])
      }
      return
    }
    let timerId = userInfo["timerId"] as? String
    // On the main thread because the channel writes both values there: the system
    // does not promise which thread calls this, and a Set is not safe to share.
    DispatchQueue.main.async {
      let cancelled = timerId.map { self.cancelledTimerIds.contains($0) } ?? false
      if self.inAppCuesActive || cancelled {
        completionHandler([])
      } else if #available(iOS 14.0, *) {
        completionHandler([.banner, .sound])
      } else {
        completionHandler([.alert, .sound])
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    // Routed here, never to super: a timer notification carries `timerId`,
    // and a Supplement reminder scheduled by flutter_local_notifications
    // carries the plugin's `payload` with kind "protocolReminder".
    if userInfo["timerId"] != nil {
      let payload: [String: Any?] = [
        "timerId": userInfo["timerId"] as? String,
        "workoutId": userInfo["workoutId"] as? String,
        "workoutExerciseId": userInfo["workoutExerciseId"] as? String,
      ]
      forwardTap(payload)
    } else if let localDate = protocolReminderDate(userInfo) {
      forwardReminderTap(localDate)
    }
    completionHandler()
  }

  // The local date a Supplement reminder's plugin payload carries, or nil when
  // the notification isn't one. The payload is JSON:
  // {"kind": "protocolReminder", "localDate": "YYYY-MM-DD"}.
  private func protocolReminderDate(_ userInfo: [AnyHashable: Any]) -> String? {
    guard
      let payload = userInfo["payload"] as? String,
      let data = payload.data(using: .utf8),
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let kind = object["kind"] as? String,
      kind == "protocolReminder",
      let localDate = object["localDate"] as? String
    else {
      return nil
    }
    return localDate
  }

  private func forwardReminderTap(_ localDate: String) {
    if flutterReady {
      timerBackgroundChannel?.invokeMethod("onProtocolReminderTapped", arguments: localDate)
    } else {
      bufferedReminderDate = localDate
    }
  }

  private func forwardTap(_ payload: [String: Any?]) {
    if flutterReady {
      timerBackgroundChannel?.invokeMethod("onTimerNotificationTapped", arguments: payload)
    } else {
      bufferedTapPayload = payload
    }
  }

  private func drainBufferedTap() {
    if let localDate = bufferedReminderDate {
      bufferedReminderDate = nil
      timerBackgroundChannel?.invokeMethod("onProtocolReminderTapped", arguments: localDate)
    }
    guard let payload = bufferedTapPayload else { return }
    bufferedTapPayload = nil
    timerBackgroundChannel?.invokeMethod("onTimerNotificationTapped", arguments: payload)
  }

  private func prepareIdentifier(_ timerId: String) -> String {
    return "prepare:\(timerId)"
  }

  private func getReadyIdentifier(_ timerId: String) -> String {
    return "getReady:\(timerId)"
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

/// Handles `perennia/backup_export`. Settings → Back up now hands a finished
/// backup here, and the system document export picker lets the user save it
/// to Files, iCloud Drive or any other file provider. Why this is a
/// foreground save and not a scheduled folder backup is recorded on
/// `BackupExportService` in Dart.
///
/// Answers `saved`, `cancelled` or `unsupported` (nothing to present the
/// picker from), or fails with `backup_write_failed` when the staging copy
/// cannot be written.
final class BackupExportChannel: NSObject, UIDocumentPickerDelegate {
  static let name = "perennia/backup_export"

  private var pendingResult: FlutterResult?
  private var stagingDirectory: URL?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "saveFile":
      saveFile(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let fileName = arguments["fileName"] as? String,
      let bytes = arguments["bytes"] as? FlutterStandardTypedData
    else {
      result(
        FlutterError(
          code: "invalid_backup_export",
          message: "Backup export payload is missing fileName or bytes.",
          details: nil
        )
      )
      return
    }
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "backup_export_busy",
          message: "A backup save picker is already open.",
          details: nil
        )
      )
      return
    }
    guard let presenter = Self.topViewController() else {
      result("unsupported")
      return
    }

    // The picker exports an existing file, so stage the backup under its
    // final name in a directory of its own, removed once the picker closes.
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent(
      (fileName as NSString).lastPathComponent)
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
      try bytes.data.write(to: fileURL, options: .atomic)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      result(
        FlutterError(
          code: "backup_write_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: fileURL, in: .exportToService)
    }
    picker.delegate = self
    pendingResult = result
    stagingDirectory = directory
    presenter.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finish("saved")
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish("cancelled")
  }

  private func finish(_ status: String) {
    let result = pendingResult
    pendingResult = nil
    if let directory = stagingDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    stagingDirectory = nil
    result?(status)
  }

  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
