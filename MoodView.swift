import SwiftUI
import SwiftData
import ARKit


@Observable
@MainActor
final class MoodService {
    private(set) var matches: [MoodMatch] = []
    private(set) var picks: [SearchResultTrack] = []
    private(set) var state: LoadState = .idle
    private(set) var profile: EnvironmentProfile?

    enum LoadState: Equatable {
        case idle, loading, ready, failed(String)
    }

    private let search = YouTubeMusicSearchService()

    func run(for profile: EnvironmentProfile) async {
        self.profile = profile
        state = .loading
        picks = []

        let ranked = MoodEngine.rank(profile)
        matches = ranked
        let top = ranked.prefix(2).map(\.mood)

        var collected: [SearchResultTrack] = []
        for mood in top {
            let queries = mood.queries.shuffled().prefix(3)
            for query in queries {
                guard let results = try? await search.search(query: query) else { continue }
                let filtered = results.filter { t in
                    guard let dur = t.duration else { return false }
                    return mood.durationRange.contains(dur)
                }
                collected.append(contentsOf: filtered.prefix(5))
                if collected.count >= 20 { break }
            }
            if collected.count >= 20 { break }
        }

        if collected.isEmpty {
            state = .failed("Не удалось найти треки. Проверь подключение к интернету.")
        } else {
            picks = Array(collected.shuffled().prefix(30))
            state = .ready
        }
    }

    func reset() {
        matches = []
        picks = []
        profile = nil
        state = .idle
    }
}


struct MoodRootView: View {
    @State private var scanner = LiDARScanner()
    @State private var moodService = MoodService()
    @State private var phase: Phase = .scanning

    enum Phase { case scanning, results }

    var body: some View {
        Group {
            if LiDARScanner.isSupported {
                switch phase {
                case .scanning:
                    ScanView(scanner: scanner) {
                        Task { await scan() }
                    }
                case .results:
                    MoodResultView(
                        service: moodService,
                        onRescan: {
                            moodService.reset()
                            scanner.reset()
                            phase = .scanning
                        }
                    )
                }
            } else {
                NoLiDARView()
            }
        }
        .onDisappear { scanner.stop() }
    }

    private func scan() async {
        scanner.stop()
        let profile = scanner.makeProfile()
        phase = .results
        await moodService.run(for: profile)
    }
}


struct ScanView: View {
    @Bindable var scanner: LiDARScanner
    let onDone: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            LiDARCameraView(scanner: scanner)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Сканирование")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("Медленно обведи камерой всю комнату")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        HStack {
                            Text(scanner.isReady
                                 ? "Данных достаточно"
                                 : "Покрытие \(Int(scanner.coverage * 100))%")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Spacer()
                            statsLabel("Поверхности", value: String(format: "%.0f м²", scanner.stats.areas.total))
                            statsLabel("Площадь", value: String(format: "%.0f м²", scanner.stats.footprintArea))
                        }

                        ProgressView(value: scanner.coverage)
                            .tint(scanner.isReady ? .green : .blue)
                            .scaleEffect(x: 1, y: 2)
                    }

                    if let hint = scanner.hint {
                        Label(hint, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.4), in: Capsule())
                    }

                    HStack(spacing: 16) {
                        Button {
                            scanner.toggleMesh()
                        } label: {
                            Label(scanner.showMesh ? "Скрыть меш" : "Показать меш",
                                  systemImage: scanner.showMesh ? "eye.slash" : "eye")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                        }

                        Spacer()

                        Button {
                            scanner.reset()
                        } label: {
                            Label("Сброс", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }

                    Button(action: onDone) {
                        Label("Подобрать музыку", systemImage: "music.note.list")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                scanner.isReady
                                    ? AnyShapeStyle(.green)
                                    : AnyShapeStyle(.white.opacity(0.25)),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                    }
                    .disabled(!scanner.isReady)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            scanner.start()
        }
    }

    private func statsLabel(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.bold()).foregroundStyle(.white)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
    }
}


struct MoodResultView: View {
    @Bindable var service: MoodService
    let onRescan: () -> Void
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    @State private var showAllMoods = false

    private var topMood: Mood? { service.matches.first?.mood }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let top = service.matches.first {
                        MoodHeaderCard(match: top, profile: service.profile)
                    }

                    switch service.state {
                    case .loading:
                        ProgressView("Подбираем треки…")
                            .padding(40)

                    case .failed(let msg):
                        ContentUnavailableView(msg,
                            systemImage: "wifi.slash",
                            description: Text("Проверь интернет и попробуй снова"))
                            .padding(20)

                    case .ready:
                        TrackPicksSection(
                            tracks: service.picks,
                            mood: topMood,
                            player: player,
                            modelContext: modelContext
                        )

                    case .idle:
                        EmptyView()
                    }

                    if service.matches.count > 1 {
                        OtherMoodsSection(
                            matches: Array(service.matches.dropFirst()),
                            expanded: $showAllMoods
                        )
                    }

                    Button(action: onRescan) {
                        Label("Сканировать ещё раз", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
                .padding(.top, 12)
            }
            .navigationTitle("Музыка для места")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


struct MoodHeaderCard: View {
    let match: MoodMatch
    let profile: EnvironmentProfile?

    var body: some View {
        VStack(spacing: 10) {
            Text(match.mood.symbol)
                .font(.system(size: 56))

            Text(match.mood.title)
                .font(.title2.bold())

            Text(match.mood.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let profile {
                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if !match.reasons.isEmpty {
                HStack(spacing: 6) {
                    ForEach(match.reasons.prefix(3), id: \.self) { reason in
                        Text(reason)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.teal.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }
}


struct TrackPicksSection: View {
    let tracks: [SearchResultTrack]
    let mood: Mood?
    let player: PlayerService
    let modelContext: ModelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Треки для тебя")
                    .font(.headline)
                Spacer()
                Button {
                    playAll()
                } label: {
                    Label("Слушать всё", systemImage: "play.fill")
                        .font(.subheadline)
                }
                .disabled(tracks.isEmpty)
            }
            .padding(.horizontal)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                MoodTrackRow(
                    track: track,
                    onPlay: { playFrom(index: index) },
                    onSave: { save(track) }
                )
                .padding(.horizontal)
            }
        }
    }

    private func playFrom(index: Int) {
        let playable = tracks.map { t in
            Track(title: t.title, artist: t.artist,
                  album: t.album ?? (mood?.title ?? "Подборка"),
                  duration: t.duration ?? 30,
                  fileName: "",
                  youtubeVideoID: t.youtubeVideoID)
        }
        player.play(playable, startAt: index)
    }

    private func playAll() { playFrom(index: 0) }

    private func save(_ track: SearchResultTrack) {
        let t = Track(title: track.title, artist: track.artist,
                      album: track.album ?? (mood?.title ?? "Подборка"),
                      duration: track.duration ?? 30,
                      fileName: "",
                      youtubeVideoID: track.youtubeVideoID)
        modelContext.insert(t)
        try? modelContext.save()
    }
}

struct MoodTrackRow: View {
    let track: SearchResultTrack
    let onPlay: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: track.artworkURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).lineLimit(1).font(.subheadline.weight(.medium))
                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            if let dur = track.duration {
                Text(formatTime(dur))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(action: onSave) {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}


struct OtherMoodsSection: View {
    let matches: [MoodMatch]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Другие варианты")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            if expanded {
                ForEach(matches) { match in
                    HStack(spacing: 12) {
                        Text(match.mood.symbol).font(.title2).frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.mood.title).font(.subheadline.bold())
                            Text(match.reasonsText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(String(format: "%.0f%%", min(match.score / 7 * 100, 99)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}


struct NoLiDARView: View {
    var body: some View {
        ContentUnavailableView(
            "LiDAR недоступен",
            systemImage: "sensor.tag.radiowaves.forward.fill",
            description: Text("Эта функция работает только на iPhone 12 Pro и новее или iPad Pro с LiDAR.")
        )
    }
}
