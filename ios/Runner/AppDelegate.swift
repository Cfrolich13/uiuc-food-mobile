import Flutter
import Security
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SessionCookieKeeper.shared.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SessionCookieKeeper") {
      SessionCookieKeeper.shared.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MapZoomGesture") {
      MapZoomGesture.register(with: registrar)
    }
  }
}

/// Which way the map's one-finger zoom (double tap, then drag) goes.
///
/// MapLibre zooms in on a drag down unless `MLNMapView.quickZoomReversed` is
/// set, which matches Apple Maps. The maplibre_gl plugin doesn't expose it, so
/// this finds the map views on screen and sets it by key (Runner doesn't link
/// MapLibre). Dart calls `setDragUpZoomsIn` whenever a map appears or the
/// setting changes.
enum MapZoomGesture {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "illini_dining/map_gestures", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "setDragUpZoomsIn", let dragUpZoomsIn = call.arguments as? Bool else {
        return result(FlutterMethodNotImplemented)
      }
      result(apply(dragUpZoomsIn: dragUpZoomsIn))
    }
  }

  /// Returns how many map views were updated.
  private static func apply(dragUpZoomsIn: Bool) -> Int {
    guard let mapViewClass = NSClassFromString("MLNMapView") else { return 0 }
    let setter = NSSelectorFromString("setQuickZoomReversed:")
    var count = 0
    func visit(_ view: UIView) {
      if view.isKind(of: mapViewClass), view.responds(to: setter) {
        view.setValue(dragUpZoomsIn, forKey: "quickZoomReversed")
        count += 1
      }
      view.subviews.forEach(visit)
    }
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      scene.windows.forEach(visit)
    }
    return count
  }
}

/// Keeps the University sign-in across app launches, the way Safari does.
///
/// WKWebView keeps cookies with an expiry date on disk but drops session
/// cookies (Microsoft's, Shibboleth's and Housing's sign-in sessions) when
/// the app quits, so every launch meant signing in again. This snapshots the
/// sign-in cookies for University, Microsoft and Duo hosts into the Keychain
/// (this device only, not backed up) whenever they change, and puts them back
/// once per launch, before the first page loads. Each site still decides how
/// long its own session is valid.
///
/// Session cookies can also vanish while the app is running: they live only in
/// WebKit's networking process, which iOS may end while the app is in the
/// background (the app keeps running, cookies with an expiry date survive).
/// So on returning to the foreground and before each refresh, saved cookies
/// missing from the store are put back; cookies still there are never touched.
final class SessionCookieKeeper: NSObject, WKHTTPCookieStoreObserver {
  static let shared = SessionCookieKeeper()

  private let keychainService = "edu.illinois.illiniDining.signInCookies"
  private let keychainAccount = "cookies"
  private let savedAtKey = "signInCookiesSavedAt"
  private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }
  private var pendingSave: DispatchWorkItem?
  private var restoring = false
  private var restored = false
  private var restoredCount = 0
  private var lastPutBack: (count: Int, at: Date)?
  private var restoreWaiters: [(Int) -> Void] = []

  func start() {
    store.add(self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(saveBeforeSuspending),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(putBackMissingOnForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
  }

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "illini_dining/session_cookies", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "restore":
        self.restore { result($0) }
      case "save":
        self.saveNow()
        result(nil)
      case "clear":
        self.deleteSnapshot()
        result(nil)
      case "describe":
        self.describe { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// University sites, Microsoft sign-in and Duo; nothing else is kept.
  static func isSignInDomain(_ domain: String) -> Bool {
    let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    return host == "illinois.edu" || host.hasSuffix(".illinois.edu")
      || host == "login.microsoftonline.com" || host == "login.microsoft.com"
      || host.hasSuffix(".duosecurity.com") || host.hasSuffix(".duo.com")
  }

  // MARK: Saving

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    guard restored, !restoring else { return }
    pendingSave?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.saveNow() }
    pendingSave = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
  }

  /// Reading the cookie store is asynchronous, so ask iOS for time to finish
  /// the save before the app is suspended.
  @objc private func saveBeforeSuspending() {
    var task = UIBackgroundTaskIdentifier.invalid
    let finish = {
      guard task != .invalid else { return }
      UIApplication.shared.endBackgroundTask(task)
      task = .invalid
    }
    task = UIApplication.shared.beginBackgroundTask(expirationHandler: finish)
    saveNow(completion: finish)
  }

  func saveNow(completion: (() -> Void)? = nil) {
    // Don't overwrite the snapshot with an empty store before it's restored.
    guard restored else {
      completion?()
      return
    }
    store.getAllCookies { [weak self] cookies in
      defer { completion?() }
      guard let self = self else { return }
      let now = Date()
      let kept = cookies.filter {
        Self.isSignInDomain($0.domain) && ($0.expiresDate.map { $0 > now } ?? true)
      }
      if kept.isEmpty {
        self.deleteSnapshot()
        return
      }
      let plist: [[String: Any]] = kept.map { cookie in
        var entry: [String: Any] = [
          "name": cookie.name, "value": cookie.value, "domain": cookie.domain,
          "path": cookie.path, "secure": cookie.isSecure, "httpOnly": cookie.isHTTPOnly,
        ]
        if let expires = cookie.expiresDate { entry["expires"] = expires }
        if let sameSite = cookie.sameSitePolicy { entry["sameSite"] = sameSite.rawValue }
        return entry
      }
      if let data = try? PropertyListSerialization.data(
        fromPropertyList: plist, format: .binary, options: 0)
      {
        self.writeSnapshot(data)
      }
    }
  }

  // MARK: Restoring

  /// Restores the saved cookies the first time it's called each launch.
  /// Later calls wait for that, then put back only saved cookies that have
  /// gone missing, so a fresher session is never replaced with an older
  /// snapshot. Completes with how many cookies were put back.
  func restore(completion: @escaping (Int) -> Void) {
    if restored { return putBackMissing(completion: completion) }
    restoreWaiters.append(completion)
    if restoring { return }
    restoring = true

    let cookies = savedCookies()
    setCookies(cookies) { [weak self] in
      guard let self = self else { return }
      self.restoring = false
      self.restored = true
      self.restoredCount = cookies.count
      let waiters = self.restoreWaiters
      self.restoreWaiters = []
      waiters.forEach { $0(cookies.count) }
    }
  }

  @objc private func putBackMissingOnForeground() {
    guard restored else { return }
    putBackMissing { _ in }
  }

  /// Puts back saved cookies the store no longer has (same name, domain and
  /// path), leaving every cookie it does have alone.
  private func putBackMissing(completion: @escaping (Int) -> Void) {
    let saved = savedCookies()
    guard !saved.isEmpty else { return completion(0) }
    store.getAllCookies { [weak self] current in
      guard let self = self else { return completion(0) }
      let present = Set(current.map(Self.identity))
      let missing = saved.filter { !present.contains(Self.identity($0)) }
      if !missing.isEmpty { self.lastPutBack = (missing.count, Date()) }
      self.setCookies(missing) { completion(missing.count) }
    }
  }

  private static func identity(_ cookie: HTTPCookie) -> String {
    let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
    return "\(cookie.name)|\(domain.lowercased())|\(cookie.path)"
  }

  private func setCookies(_ cookies: [HTTPCookie], completion: @escaping () -> Void) {
    let group = DispatchGroup()
    for cookie in cookies {
      group.enter()
      store.setCookie(cookie) { group.leave() }
    }
    group.notify(queue: .main, execute: completion)
  }

  /// The unexpired cookies in the Keychain snapshot.
  private func savedCookies() -> [HTTPCookie] {
    var cookies: [HTTPCookie] = []
    if let data = readSnapshot(),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [[String: Any]]
    {
      let now = Date()
      cookies = plist.compactMap { entry -> HTTPCookie? in
        var properties: [HTTPCookiePropertyKey: Any] = [
          .name: entry["name"] ?? "", .value: entry["value"] ?? "",
          .domain: entry["domain"] ?? "", .path: entry["path"] ?? "/",
        ]
        if entry["secure"] as? Bool == true { properties[.secure] = "TRUE" }
        if entry["httpOnly"] as? Bool == true { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires = entry["expires"] as? Date {
          guard expires > now else { return nil }
          properties[.expires] = expires
        }
        if let sameSite = entry["sameSite"] as? String { properties[.sameSitePolicy] = sameSite }
        return HTTPCookie(properties: properties)
      }
    }
    return cookies
  }

  // MARK: Diagnostics

  /// Names and lifetimes of the sign-in cookies, never their values, for the
  /// app's sign-in diagnostics screen.
  func describe(completion: @escaping ([String: Any]) -> Void) {
    store.getAllCookies { [weak self] cookies in
      guard let self = self else { return completion([:]) }
      let live: [[String: Any]] = cookies.filter { Self.isSignInDomain($0.domain) }.map { cookie in
        var entry: [String: Any] = [
          "name": cookie.name, "host": cookie.domain, "session": cookie.isSessionOnly,
        ]
        if let expires = cookie.expiresDate { entry["expires"] = Self.millis(expires) }
        return entry
      }
      var report: [String: Any] = ["cookies": live]
      if let data = self.readSnapshot(),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
          as? [[String: Any]]
      {
        report["savedCount"] = plist.count
      } else {
        report["savedCount"] = 0
      }
      if let savedAt = UserDefaults.standard.object(forKey: self.savedAtKey) as? Date {
        report["savedAt"] = Self.millis(savedAt)
      }
      if self.restored { report["restoredAtLaunch"] = self.restoredCount }
      if let putBack = self.lastPutBack {
        report["putBackCount"] = putBack.count
        report["putBackAt"] = Self.millis(putBack.at)
      }
      completion(report)
    }
  }

  private static func millis(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

  // MARK: Keychain

  private var keychainQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
  }

  private func readSnapshot() -> Data? {
    var query = keychainQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
  }

  private func writeSnapshot(_ data: Data) {
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      SecItemAdd(keychainQuery.merging(attributes) { $1 } as CFDictionary, nil)
    }
    UserDefaults.standard.set(Date(), forKey: savedAtKey)
  }

  func deleteSnapshot() {
    SecItemDelete(keychainQuery as CFDictionary)
    UserDefaults.standard.removeObject(forKey: savedAtKey)
  }
}
