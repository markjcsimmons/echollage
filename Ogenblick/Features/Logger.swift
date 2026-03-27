import Foundation
import os.log
import FirebaseCrashlytics

enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.marksimmons.ogenblick"
    
    // MARK: - Categories
    enum Category: String {
        case audio = "Audio"
        case recording = "Recording"
        case export = "Export"
        case editor = "Editor"
        case purchase = "Purchase"
        case network = "Network"
        case general = "General"
    }
    
    // MARK: - Logging Methods
    
    static func info(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let log = OSLog(subsystem: subsystem, category: category.rawValue)
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: log, type: .info, message, fileName, function, line)
        Crashlytics.crashlytics().log("\(category.rawValue): \(message)")
    }
    
    static func warning(_ message: String, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let log = OSLog(subsystem: subsystem, category: category.rawValue)
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: log, type: .default, message, fileName, function, line)
        Crashlytics.crashlytics().log("\(category.rawValue) WARNING: \(message)")
    }
    
    static func error(_ message: String, error: Error? = nil, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let log = OSLog(subsystem: subsystem, category: category.rawValue)
        
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        
        os_log("%{public}@ [%{public}@:%{public}@:%d]", log: log, type: .error, fullMessage, fileName, function, line)
        Crashlytics.crashlytics().log("\(category.rawValue) ERROR: \(fullMessage)")
    }
    
    static func critical(_ message: String, error: Error? = nil, category: Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
        Logger.error(message, error: error, category: category, file: file, function: function, line: line)
        
        let crashlytics = Crashlytics.crashlytics()
        crashlytics.log("\(category.rawValue) CRITICAL: \(message)")
        if let error = error {
            crashlytics.record(error: error)
        } else {
            crashlytics.record(error: NSError(domain: category.rawValue, code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
    
    static func setUserID(_ userID: String?) {
        Crashlytics.crashlytics().setUserID(userID)
    }
    
    static func setCustomValue(_ value: Any, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }
}
