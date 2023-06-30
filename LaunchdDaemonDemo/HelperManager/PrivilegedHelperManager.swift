//
//  PrivilegedHelperManager+Legacy.swift
//  LaunchdDaemonDemo
//
//  Created by fakepinge on 2023/6/30.
//

import AppKit
import Cocoa
import ServiceManagement
import RxSwift
import RxCocoa

@objcMembers
class PrivilegedHelperManager: NSObject {
    
    enum HelperStatus {
        case installed
        case noFound
        case needUpdate
    }
    
    static let shared = PrivilegedHelperManager()
    static let machServiceName = "com.fakepinge.LaunchdDaemon.helper"
    var connectionSuccessBlock: (() -> Void)?
    
    private var useLegacyInstall = false

    override init() {
        super.init()
        initAuthorizationRef()
    }

    /// 检测安装
    func checkInstall() {
        getHelperStatus { [weak self] status in
            guard let self = self else {return}
            switch status {
            case .noFound:
                if #available(macOS 13, *) {
                    let url = URL(string: "/Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist")!
                    let status = SMAppService.statusForLegacyPlist(at: url)
                    if status == .requiresApproval {
                        let alert = NSAlert()
                        let notice = "当前App需要通过后台Daemon进程来启动加速，请在\"系统偏好设置->登录项->允许在后台 中\"允许当前App"
                        let addition = "如果在设置里没找到当前App，可以尝试重置守护程序"
                        alert.messageText = notice + "\n" + addition
                        alert.addButton(withTitle: "打开系统登录项设置")
                        alert.addButton(withTitle: "重置守护程序")
                        if alert.runModal() == .alertFirstButtonReturn {
                            SMAppService.openSystemSettingsLoginItems()
                        } else {
                            self.removeInstallHelper()
                        }
                    }
                }
                fallthrough
            case .needUpdate:
                if Thread.isMainThread {
                    self.notifyInstall()
                } else {
                    DispatchQueue.main.async {
                        self.notifyInstall()
                    }
                }
            case .installed:
                self.connectionSuccessBlock?()
            }
        }
    }

    /// Create an empty AuthorizationRef
    private func initAuthorizationRef() {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, AuthorizationFlags(), &authRef)
        if status != OSStatus(errAuthorizationSuccess) {
            return
        }
    }

    /// Install new helper daemon
    private func installHelperDaemon() -> DaemonInstallResult {
        defer {
            
        }
        // Create authorization reference for the user
        var authRef: AuthorizationRef?
        var authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        // Check if the reference is valid
        guard authStatus == errAuthorizationSuccess else {
            return .authorizationFail
        }

        // Ask user for the admin privileges to install the
        var authItem = AuthorizationItem(name: (kSMRightBlessPrivilegedHelper as NSString).utf8String!, valueLength: 0, value: nil, flags: 0)
        var authRights = withUnsafeMutablePointer(to: &authItem) { pointer in
            AuthorizationRights(count: 1, items: pointer)
        }
        let flags: AuthorizationFlags = [[], .interactionAllowed, .extendRights, .preAuthorize]
        authStatus = AuthorizationCreate(&authRights, nil, flags, &authRef)
        defer {
            if let ref = authRef {
                AuthorizationFree(ref, [])
            }
        }
        // Check if the authorization went succesfully
        guard authStatus == errAuthorizationSuccess else {
            return .getAdminFail
        }

        // Launch the privileged helper using SMJobBless tool
        var error: Unmanaged<CFError>?
        if SMJobBless(kSMDomainSystemLaunchd, PrivilegedHelperManager.machServiceName as CFString, authRef, &error) == false {
            let blessError = error!.takeRetainedValue() as Error
            return .blessError((blessError as NSError).code)
        }

        return .success
    }

    private func getHelperStatus(callback: @escaping ((HelperStatus) -> Void)) {
        var called = false
        let reply: ((HelperStatus) -> Void) = {
            status in
            if called {return}
            called = true
            callback(status)
        }

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + PrivilegedHelperManager.machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let helperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String else {
            reply(.noFound)
            return
        }
        let helperFileExists = FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)")
        if !helperFileExists {
            reply(.noFound)
            return
        }
        
        reply(.installed)

    }
}

extension PrivilegedHelperManager {
    private func notifyInstall() {
        if useLegacyInstall {
            useLegacyInstall = false
            legacyInstallHelper()
            checkInstall()
            return
        }

        let result = installHelperDaemon()
        if case .success = result {
            checkInstall()
            return
        }
        result.alertAction()
        let ret = result.shouldRetryLegacyWay()
        useLegacyInstall = ret.0
        let isCancle = ret.1
        if !isCancle, useLegacyInstall  {
            checkInstall()
        } else if isCancle, !useLegacyInstall {
            NSAlert.alert(with: "获取管理员授权失败，用户主动取消授权！")
        }
    }
}

private struct AppAuthorizationRights {
    static let rightName: NSString = "\(PrivilegedHelperManager.machServiceName).config" as NSString
    static let rightDefaultRule: Dictionary = adminRightsRule
    static let rightDescription: CFString = "ProxyConfigHelper wants to configure your proxy setting'" as CFString
    static var adminRightsRule: [String: Any] = ["class": "user",
                                                 "group": "admin",
                                                 "timeout": 0,
                                                 "version": 1]
}

private enum DaemonInstallResult {
    case success
    case authorizationFail
    case getAdminFail
    case blessError(Int)
    var alertContent: String {
        switch self {
        case .success:
            return ""
        case .authorizationFail: return "Failed to create authorization!"
        case .getAdminFail: return "The user actively cancels the authorization, Failed to get admin authorization! "
        case let .blessError(code):
            switch code {
            case kSMErrorInternalFailure: return "blessError: kSMErrorInternalFailure"
            case kSMErrorInvalidSignature: return "blessError: kSMErrorInvalidSignature"
            case kSMErrorAuthorizationFailure: return "blessError: kSMErrorAuthorizationFailure"
            case kSMErrorToolNotValid: return "blessError: kSMErrorToolNotValid"
            case kSMErrorJobNotFound: return "blessError: kSMErrorJobNotFound"
            case kSMErrorServiceUnavailable: return "blessError: kSMErrorServiceUnavailable"
            case kSMErrorJobMustBeEnabled: return "ClashX Helper is disabled by other process. Please run \"sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)\" in your terminal. The command has been copied to your pasteboard"
            case kSMErrorInvalidPlist: return "blessError: kSMErrorInvalidPlist"
            default:
                return "bless unknown error:\(code)"
            }
        }
    }
    
    // 是否启动传统安装、是否是主动取消安装
    func shouldRetryLegacyWay() -> (Bool, Bool) {
        switch self {
        case .success: return (false, false)
        case let .blessError(code):
            switch code {
            case kSMErrorJobMustBeEnabled:
                return (false, false)
            default:
                return (true, false)
            }
        case .authorizationFail:
            return (true, false)
        case .getAdminFail:
            return (false, true)
        }
    }

    func alertAction() {
        switch self {
        case let .blessError(code):
            switch code {
            case kSMErrorJobMustBeEnabled:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)", forType: .string)
            default:
                break
            }
        default:
            break
        }
    }
}

extension NSAlert {
    static func alert(with text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }
}
