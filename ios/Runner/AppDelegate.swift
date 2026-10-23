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
final class SessionCookieKeeper: NSObject, WKHTTPCookieStoreObserver {
  static let shared = SessionCookieKeeper()

  private let keychainService = "edu.illinois.illiniDining.signInCookies"
  private let keychainAccount = "cookies"
  private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }
  private var pendingSave: DispatchWorkItem?
  private var restoring = false
  private var restored = false
  private var restoreWaiters: [(Int) -> Void] = []

  func start() {
    store.add(self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(saveNow),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "illini_dining/session_cookies", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "restore":
        self.restoreOnce { result($0) }
      case "save":
        self.saveNow()
        result(nil)
      case "clear":
        self.deleteSnapshot()
        result(nil)
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

  @objc func saveNow() {
    // Don't overwrite the snapshot with an empty store before it's restored.
    guard restored else { return }
    store.getAllCookies { [weak self] cookies in
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

  /// Restores the saved cookies the first time it's called each launch;
  /// later calls just wait for that to finish, so a fresher session is never
  /// replaced with an older snapshot.
  func restoreOnce(completion: @escaping (Int) -> Void) {
    if restored { return completion(0) }
    restoreWaiters.append(completion)
    if restoring { return }
    restoring = true

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

    let group = DispatchGroup()
    for cookie in cookies {
      group.enter()
      store.setCookie(cookie) { group.leave() }
    }
    group.notify(queue: .main) { [weak self] in
      guard let self = self else { return }
      self.restoring = false
      self.restored = true
      let waiters = self.restoreWaiters
      self.restoreWaiters = []
      waiters.forEach { $0(cookies.count) }
    }
  }

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
  }

  func deleteSnapshot() {
    SecItemDelete(keychainQuery as CFDictionary)
  }
}
