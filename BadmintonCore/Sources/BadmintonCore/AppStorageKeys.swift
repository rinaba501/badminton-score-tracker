//
//  AppStorageKeys.swift
//  BadmintonCore
//
//  Single source of truth for every UserDefaults / @AppStorage key the app
//  persists. Only the key *strings* live here — typed defaults stay at each
//  @AppStorage declaration site, because several reference app-only types
//  (CourtTheme, SettingsView.GameMode). New persisted keys must be added
//  here, never as inline string literals — and if the new key should sync
//  across devices, it must ALSO be wired into SupabaseSyncEngine: history/
//  roster/club/challenge/reaction keys go through their existing enqueue*
//  methods, and scalar settings go through enqueueSettingsChange (see
//  SettingsSnapshot).
//

import Foundation

public enum AppStorageKeys {
    public static let myName = "myName"
    public static let matchMyName = "matchMyName"
    public static let matchOpponentName = "matchOpponentName"
    // Phase 10b (#315): the far/opponent slot's picked Friend's participantId,
    // when picked from Friends — "" otherwise. Same per-device match-config
    // exclusion as matchOpponentName, never synced; read once at save time to
    // tag MatchRecord.opponentParticipantId.
    public static let matchOpponentParticipantId = "matchOpponentParticipantId"
    public static let matchMyPartnerName = "matchMyPartnerName"
    public static let matchOpponentPartnerName = "matchOpponentPartnerName"
    // PreMatchView's club picker (#169); UUID string, "" = Personal. Same
    // per-device match-config exclusion as matchMyName et al. — never synced.
    public static let matchClubId = "matchClubId"
    // PreMatchView's Official/Practice toggle, shown alongside matchClubId
    // when a club is selected and tracks standings. Bool, defaults true
    // (Official). Same per-device, never-synced convention as matchClubId.
    public static let matchIsOfficial = "matchIsOfficial"
    public static let playerRoster = "playerRoster"
    public static let matchHistory = "matchHistory"
    public static let clubs = "clubs"
    // Roadmap Phase 5 backlog (#162): club-scoped only, no personal/KV
    // fallback — see ChallengeRecord.swift and AppStore.saveChallenges.
    public static let challenges = "challenges"
    // Roadmap Phase 5 backlog (#164): club-scoped only, no personal/KV
    // fallback — see ReactionRecord.swift and AppStore.saveReactions.
    public static let reactions = "reactions"
    // Friends v1 (graph-only): synced via the `friend_requests` table, no
    // KV fallback — see FriendRequest.swift and AppStore.saveFriendRequests.
    public static let friendRequests = "friendRequests"
    // Roadmap Phase 10a: synced via the `match_invites` table, no KV
    // fallback — see MatchInvite.swift and AppStore.saveMatchInvites.
    public static let matchInvites = "matchInvites"
    // Friends v1: per-device cache of `currentUserId()`'s result (a Supabase
    // `auth.uid()`, stable for the life of the account) — it's a per-device
    // identity cache, not synced data.
    public static let myParticipantId = "myParticipantId"
    public static let playerSortOrder = "playerSortOrder"
    public static let pointsToWin = "pointsToWin"
    public static let gamesInMatch = "gamesInMatch"
    public static let courtTheme = "courtTheme"
    // iOS-only (Watch has its own GameView, unaffected) — which of the 3
    // GameView visual styles to render. Synced via SettingsSnapshot even
    // though only iOS reads it, matching every other scalar setting.
    public static let gameScreenStyle = "gameScreenStyle"
    public static let announceScore = "announceScore"
    public static let enableSounds = "enableSounds"
    public static let enableCrownScoring = "enableCrownScoring"
    public static let timeModeEnabled = "timeModeEnabled"
    public static let timeLimitMinutes = "timeLimitMinutes"
    // Opt-in reminder for real badminton end-changes (BWF Law 12.1): alerts
    // the scorekeeper and flips which side renders first on the Game screen
    // after each game, and mid-way through the deciding game once the
    // leading score crosses BadmintonMatch.isCourtChangeThreshold. Purely a
    // display/reminder toggle — never touches Side.me/.opponent scoring
    // identity. Bool, defaults false like timeModeEnabled.
    public static let courtChangeRemindersEnabled = "courtChangeRemindersEnabled"
    public static let gameMode = "gameMode"
    public static let localPlayerId = "localPlayerId"
    // #161 activity feed: "last viewed" timestamp per club (JSON dictionary,
    // club id string -> Date), so an unread marker can compare against it.
    // Synced across a person's own devices via SettingsSnapshot — merged
    // per-club (max date), never overwritten, on apply (see
    // AppStore.applyRemoteSettings) so a stale device can't re-raise a dot.
    public static let clubLastViewedActivity = "clubLastViewedActivity"
    // Whether the user's personal (clubId == nil) roster and match history
    // become read-only visible to every accepted friend, via the
    // friend_can_view_history RLS policy on players/match_records. Synced
    // via SettingsSnapshot (blind overwrite, like the other plain Bool
    // settings).
    public static let shareHistoryWithFriends = "shareHistoryWithFriends"
    // Per-field friend-visibility toggles for profile data (avatar/gender/
    // birthday/introduction) and derived stats — same synced-Bool pattern as
    // shareHistoryWithFriends, but each gates one field of
    // FriendIdentitySnapshot/FriendStatsSnapshot independently. Name has no
    // toggle (see SettingsSnapshot.swift doc comment).
    public static let shareAvatarWithFriends = "shareAvatarWithFriends"
    public static let shareGenderWithFriends = "shareGenderWithFriends"
    public static let shareBirthdayWithFriends = "shareBirthdayWithFriends"
    public static let shareIntroductionWithFriends = "shareIntroductionWithFriends"
    public static let shareStatsWithFriends = "shareStatsWithFriends"
    // Personal profile fields, synced via SettingsSnapshot (blind overwrite).
    // Only ever leave the device via FriendIdentitySnapshot, gated by the
    // matching share*WithFriends toggle above — see ProfileView.swift.
    public static let gender = "gender"
    public static let birthday = "birthday"
    public static let introduction = "introduction"
    // Local cache of friends' shared roster/history (read-only, never merged
    // into playerRoster/matchHistory) — see FriendHistorySnapshot.swift and
    // AppStore.applyRemoteFriendActivity.
    public static let friendActivity = "friendActivity"
    // Local caches of friends' shared identity/stats snapshots (read-only,
    // same never-merged-into-your-own-data convention as friendActivity) —
    // see FriendIdentitySnapshot.swift/FriendStatsSnapshot.swift and
    // AppStore.applyRemoteFriendIdentity/applyRemoteFriendStats.
    public static let friendIdentities = "friendIdentities"
    public static let friendStats = "friendStats"

    // Monetization: local cache of owned StoreKit product IDs (JSON-encoded
    // Set<String>, via OwnedProductsCodec) so entitlement-gated UI has an
    // instant launch state before Transaction.currentEntitlements resolves.
    // StoreKit is the cross-device source of truth (per Apple ID) — this key
    // is device-local and must NEVER be synced.
    public static let ownedProductIds = "ownedProductIds"

    // Supabase sync (Roadmap Phase 9c). Local device state for the Supabase
    // transport: whether this device has opted into Supabase as its sync
    // backend — see AppStore.activateSupabaseSync()/deactivateSupabaseSync()
    // and SupabaseSyncEngine.swift. Deliberately excluded from
    // eraseAllDataResetKeys — blindly resetting this while SupabaseSyncEngine
    // is the live AppStore.syncEngine would desync the flag from AppStore's
    // actual in-memory state. Not synced via SettingsSnapshot — this decides
    // *which transport* runs on this device.
    public static let supabaseAccountLinked = "supabaseAccountLinked"
    // Whether the first-launch "what should we call you?" prompt has been
    // shown (skip or save both count) — device-local, never synced, so a
    // fresh device always gets asked once regardless of other devices'
    // state. Doesn't gate app usage: skipping leaves myName at its default
    // and the app fully usable (local-first invariant) — Friends/Clubs
    // carry a lighter one-time-per-visit nudge as a backstop instead.
    public static let didPromptForName = "didPromptForName"

    // Erase All My Data (#264): every scalar setting key that should reset to
    // its fresh-install default when the user erases their data, so the app
    // reads back exactly as it would on first launch. Deliberately excludes:
    // content-array keys (playerRoster/matchHistory/clubs/challenges/
    // reactions/friendRequests/friendActivity/friendIdentities/friendStats —
    // erased through their own AppStore.save* diffing instead, not raw key
    // removal), myParticipantId (device identity cache, not user data), and
    // ownedProductIds (a StoreKit purchase cache tied to the Apple ID, never
    // app data).
    public static let eraseAllDataResetKeys: [String] = [
        myName, matchMyName, matchOpponentName, matchOpponentParticipantId, matchMyPartnerName, matchOpponentPartnerName,
        matchClubId, matchIsOfficial, playerSortOrder,
        pointsToWin, gamesInMatch, courtTheme, gameScreenStyle,
        announceScore, enableSounds, enableCrownScoring, timeModeEnabled, timeLimitMinutes,
        courtChangeRemindersEnabled, gameMode, localPlayerId, clubLastViewedActivity,
        shareHistoryWithFriends, shareAvatarWithFriends, shareGenderWithFriends,
        shareBirthdayWithFriends, shareIntroductionWithFriends, shareStatsWithFriends,
        gender, birthday, introduction,
        didPromptForName
    ]
}

/// Codec for `AppStorageKeys.clubLastViewedActivity`'s `Data`-backed
/// `[String: Date]` (club id string -> last-viewed date); `@AppStorage`
/// has no native `[String: Date]` support, so views decode/encode through
/// this instead of hand-rolling `JSONEncoder`/`JSONDecoder` per call site.
public enum ClubActivityCodec {
    public static func decode(_ data: Data) -> [String: Date] {
        (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    public static func encode(_ lastViewed: [String: Date]) -> Data {
        (try? JSONEncoder().encode(lastViewed)) ?? Data()
    }
}
