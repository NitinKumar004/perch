import Testing
import PerchModuleKit
import PerchConfig
@testable import PerchApp

/// A sound player double so notification delivery is testable without real audio.
@MainActor
final class FakeSoundPlayer: AlertSoundPlaying {
    var played: [AlertSound] = []
    func play(_ sound: AlertSound) { played.append(sound) }
}

@Suite @MainActor struct AlertSoundTests {
    @Test func resolveMapsTheSetting() {
        #expect(AlertSound.resolve("none") == .silent)
        #expect(AlertSound.resolve("default") == .systemDefault)
        #expect(AlertSound.resolve("") == .systemDefault)
        #expect(AlertSound.resolve("Glass") == .named("Glass"))
        #expect(AlertSound.resolve("NotARealSound") == .systemDefault)   // unknown → audible default
    }

    @Test func osNotificationSoundMapping() {
        // The OS notification carries the default sound only for .systemDefault;
        // for .named we play it ourselves, and .silent is silent — both nil so
        // the OS banner doesn't double the chime.
        #expect(AlertSound.systemDefault.osNotificationSound != nil)
        #expect(AlertSound.silent.osNotificationSound == nil)
        #expect(AlertSound.named("Glass").osNotificationSound == nil)
    }

    private func notifier(_ sound: String, player: FakeSoundPlayer) -> Notifier {
        let n = Notifier(soundPlayer: player)
        n.configure(GlobalSettings(notificationSound: sound))
        return n
    }
    private func alert(_ id: String) -> ModuleAlert { ModuleAlert(id: id, title: "t", body: "b") }

    @Test func namedSoundIsPlayedOnDelivery() {
        let player = FakeSoundPlayer()
        let n = notifier("Glass", player: player)
        #expect(n.post(alert("a")) == .delivered)
        #expect(player.played == [.named("Glass")])
    }

    @Test func defaultAndNoneDoNotPlayManually() {
        // "default" rides on the OS notification's own sound; "none" is silent —
        // neither asks the manual player to do anything.
        let p1 = FakeSoundPlayer(); _ = notifier("default", player: p1).post(alert("d"))
        let p2 = FakeSoundPlayer(); _ = notifier("none", player: p2).post(alert("n"))
        #expect(p1.played.isEmpty)
        #expect(p2.played.isEmpty)
    }

    @Test func duplicateAlertDoesNotReplaySound() {
        let player = FakeSoundPlayer()
        let n = notifier("Glass", player: player)
        _ = n.post(alert("same"))
        #expect(n.post(alert("same")) == .duplicate)
        #expect(player.played == [.named("Glass")])   // played once, not twice
    }

    // playConfiguredSound() is the path for a surfacing alert that ISN'T a posted
    // native notification (the auto-open "why" banner). Unlike post(), it plays
    // the DEFAULT sound too (there's no OS notification to carry it).
    @Test func playConfiguredSoundPlaysNamed() {
        let player = FakeSoundPlayer()
        notifier("Hero", player: player).playConfiguredSound()
        #expect(player.played == [.named("Hero")])
    }

    @Test func playConfiguredSoundPlaysDefaultBeep() {
        let player = FakeSoundPlayer()
        notifier("default", player: player).playConfiguredSound()
        #expect(player.played == [.systemDefault])   // audible even without a native notification
    }

    @Test func playConfiguredSoundStaysSilentForNone() {
        let player = FakeSoundPlayer()
        notifier("none", player: player).playConfiguredSound()
        #expect(player.played.isEmpty)
    }
}
