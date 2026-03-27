import Foundation
import FirebaseAnalytics

enum AnalyticsService {

    // MARK: - Export flow

    static func logExportStarted(backgroundType: String) {
        Analytics.logEvent("export_started", parameters: [
            "background_type": backgroundType
        ])
    }

    static func logExportCompleted(backgroundType: String, durationSeconds: Double) {
        Analytics.logEvent("export_completed", parameters: [
            "background_type": backgroundType,
            "audio_duration_seconds": durationSeconds
        ])
    }

    // MARK: - Sharing

    static func logSharePresented() {
        Analytics.logEvent("share_presented", parameters: nil)
    }

    // MARK: - Editor

    static func logBackgroundSelected(type backgroundType: String) {
        Analytics.logEvent("background_selected", parameters: [
            "background_type": backgroundType
        ])
    }

    // MARK: - Audio / Music

    static func logAudioRecorded(durationSeconds: Double) {
        Analytics.logEvent("audio_recorded", parameters: [
            "duration_seconds": durationSeconds
        ])
    }

    static func logMusicIdentified(title: String, artist: String) {
        Analytics.logEvent("music_identified", parameters: [
            "title": String(title.prefix(100)),
            "artist": String(artist.prefix(100))
        ])
    }

    // MARK: - Paywall

    static func logPaywallShown(freeExportsRemaining: Int) {
        Analytics.logEvent("paywall_shown", parameters: [
            "free_exports_remaining": freeExportsRemaining
        ])
    }

    static func logSubscriptionPurchased(productId: String) {
        Analytics.logEvent("subscription_purchased", parameters: [
            "product_id": productId
        ])
    }

    // MARK: - User identity

    static func setUserID(_ userID: String) {
        Analytics.setUserID(userID)
    }
}
