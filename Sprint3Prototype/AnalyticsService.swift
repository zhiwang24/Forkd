import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Thin wrapper so we can log analytics events from SwiftUI views without referencing
/// Firebase everywhere. When FirebaseAnalytics isn’t linked (e.g. in Preview builds),
/// calls degrade gracefully.
final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    func logAppOpen(source: String? = nil) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: ["source": source ?? "direct"])
        #else
        debugPrint("[Analytics] app_open", source ?? "direct")
        #endif
    }

    func logScreenView(_ name: String, hallID: String? = nil) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name,
            "hall_id": hallID ?? ""
        ])
        #else
        debugPrint("[Analytics] screen_view", name, hallID ?? "")
        #endif
    }

    func logWaitVoteQueued(hallID: String, minutes: Int, votesRemaining: Int) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("wait_vote_queued", parameters: [
            "hall_id": hallID,
            "minutes": minutes,
            "votes_remaining": votesRemaining
        ])
        #else
        debugPrint("[Analytics] wait_vote_queued", hallID, minutes, votesRemaining)
        #endif
    }

    func logWaitTimeCommitted(hallID: String, minutes: Int, wasAggregated: Bool) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent("wait_time_committed", parameters: [
            "hall_id": hallID,
            "minutes": minutes,
            "aggregated": wasAggregated
        ])
        #else
        debugPrint("[Analytics] wait_time_committed", hallID, minutes, wasAggregated)
        #endif
    }
}
