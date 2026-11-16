import Foundation


enum SizeClass: Sendable {
    case tiny, small, medium, large, huge

    var title: String {
        switch self {
        case .tiny: "Тесное помещение"
        case .small: "Небольшая комната"
        case .medium: "Просторная комната"
        case .large: "Большое помещение"
        case .huge: "Огромный зал"
        }
    }
}

enum LightLevel: Sendable {
    case dark, dim, normal, bright

    var title: String {
        switch self {
        case .dark: "темно"
        case .dim: "полумрак"
        case .normal: "нормальный свет"
        case .bright: "яркий свет"
        }
    }
}

enum LightTone: Sendable {
    case warm, neutral, cool

    var title: String {
        switch self {
        case .warm: "тёплый оттенок"
        case .neutral: "нейтральный оттенок"
        case .cool: "холодный оттенок"
        }
    }
}

enum DayPart: Sendable {
    case night, morning, day, evening

    static func current(for date: Date = Date()) -> DayPart {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .morning
        case 11..<18: .day
        case 18..<22: .evening
        default: .night
        }
    }

    var title: String {
        switch self {
        case .night: "ночь"
        case .morning: "утро"
        case .day: "день"
        case .evening: "вечер"
        }
    }
}


struct EnvironmentProfile: Identifiable, Sendable {
    let id = UUID()

    var areas: SurfaceAreas
    var footprintArea: Float
    var ceilingHeight: Float?
    var boundingHeight: Float
    var ambientIntensity: Double
    var colorTemperature: Double
    var date: Date = Date()

    var height: Float { ceilingHeight ?? max(boundingHeight, 2.4) }
    var volume: Float { footprintArea * height }

    var sizeClass: SizeClass {
        let v = volume
        if v < 20 { return .tiny }
        if v < 45 { return .small }
        if v < 110 { return .medium }
        if v < 300 { return .large }
        return .huge
    }

    var lightLevel: LightLevel {
        if ambientIntensity < 150 { return .dark }
        if ambientIntensity < 450 { return .dim }
        if ambientIntensity < 1000 { return .normal }
        return .bright
    }

    var lightTone: LightTone {
        if colorTemperature < 4800 { return .warm }
        if colorTemperature > 7000 { return .cool }
        return .neutral
    }

    var dayPart: DayPart { DayPart.current(for: date) }

    var clutter: Float {
        let total = areas.total
        guard total > 0 else { return 0 }
        return (areas.other + areas.table + areas.seat) / total
    }

    var windowShare: Float {
        let total = areas.total
        return total > 0 ? areas.window / total : 0
    }

    var isOutdoor: Bool {
        let total = areas.total
        guard total > 0 else { return false }
        return areas.ceiling / total < 0.02
            && areas.floor > 8
            && lightLevel == .bright
            && dayPart != .night
    }

    var summary: String {
        let place = isOutdoor ? "Открытое пространство" : sizeClass.title
        return [place, lightLevel.title, lightTone.title, dayPart.title].joined(separator: " · ")
    }
}


enum Mood: String, CaseIterable, Identifiable, Sendable {
    case cozyLofi, nightAmbient, focus, cafeJazz, morningAcoustic, energy, openAir, cinematic

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cozyLofi: "1"
        case .nightAmbient: "2"
        case .focus: "3"
        case .cafeJazz: "4"
        case .morningAcoustic: "5"
        case .energy: "6"
        case .openAir: "7"
        case .cinematic: "8"
        }
    }

    var title: String {
        switch self {
        case .cozyLofi: "Уютный лоу-фай"
        case .nightAmbient: "Ночной эмбиент"
        case .focus: "Фокус"
        case .cafeJazz: "Кафе-джаз"
        case .morningAcoustic: "Свежее утро"
        case .energy: "Заряд энергии"
        case .openAir: "На свежем воздухе"
        case .cinematic: "Кино-простор"
        }
    }

    var subtitle: String {
        switch self {
        case .cozyLofi: "Спокойный лоу-фай для небольшой уютной комнаты"
        case .nightAmbient: "Тихие длинные звуки на ночь, без яркого света"
        case .focus: "Музыка без слов, чтобы работать и учиться"
        case .cafeJazz: "Джаз и босса-нова, как в небольшом кафе"
        case .morningAcoustic: "Акустика и лёгкий поп для светлой комнаты"
        case .energy: "Энергичная музыка, если есть где подвигаться"
        case .openAir: "Для прогулки, лета и открытого воздуха"
        case .cinematic: "Оркестр и пост-рок для больших высоких помещений"
        }
    }

    var queries: [String] {
        switch self {
        case .cozyLofi:
            ["lofi hip hop chill", "chillhop cozy", "cozy acoustic evening", "bedroom pop chill", "lofi jazz beats"]
        case .nightAmbient:
            ["ambient music for sleep", "dark ambient night", "slowed reverb night drive", "calm piano night", "dreamy ambient electronic"]
        case .focus:
            ["deep focus instrumental", "study music no lyrics", "brain food electronic focus", "post rock instrumental", "classical piano focus"]
        case .cafeJazz:
            ["coffee shop jazz", "bossa nova cafe", "smooth jazz piano", "jazz lounge", "vintage swing jazz"]
        case .morningAcoustic:
            ["acoustic morning songs", "indie folk morning", "feel good acoustic pop", "sunny day songs", "soft pop morning"]
        case .energy:
            ["workout electronic music", "upbeat dance hits", "energy pop hits", "house music energy", "running playlist songs"]
        case .openAir:
            ["summer road trip songs", "indie rock outdoors", "reggae chill sun", "festival anthems", "folk adventure songs"]
        case .cinematic:
            ["epic cinematic orchestral", "post rock cinematic", "neoclassical piano ambient", "film score emotional", "orchestral trailer music"]
        }
    }

    var durationRange: ClosedRange<Double> {
        switch self {
        case .nightAmbient, .cinematic: 90...1500
        default: 90...660
        }
    }
}

struct MoodMatch: Identifiable, Sendable {
    let mood: Mood
    let score: Double
    let reasons: [String]
    var id: String { mood.rawValue }

    var reasonsText: String {
        reasons.isEmpty ? "универсальный выбор" : reasons.joined(separator: ", ")
    }
}


private struct Scorer {
    var score = 0.0
    var reasons: [String] = []

    mutating func add(_ points: Double, _ condition: Bool, _ reason: String) {
        guard condition else { return }
        score += points
        reasons.append(reason)
    }
}

enum MoodEngine {
    static func rank(_ p: EnvironmentProfile) -> [MoodMatch] {
        let size = p.sizeClass
        let light = p.lightLevel
        let tone = p.lightTone
        let part = p.dayPart

        let indoor = !p.isOutdoor
        let compact = size == .tiny || size == .small
        let roomy = size == .medium || size == .large
        let furnished = p.clutter > 0.5
        let sparse = p.clutter < 0.3

        func match(_ mood: Mood, _ rules: (inout Scorer) -> Void) -> MoodMatch {
            var s = Scorer()
            rules(&s)
            return MoodMatch(mood: mood, score: s.score, reasons: s.reasons)
        }

        let all: [MoodMatch] = [
            match(.cozyLofi) { s in
                s.add(1.5, compact && indoor, "небольшое пространство")
                s.add(1.5, tone == .warm, "тёплый свет")
                s.add(1.0, furnished, "много мебели и вещей")
                s.add(0.5, p.areas.seat > 1, "есть диван или кресла")
                s.add(1.0, part == .evening, "вечер")
            },
            match(.nightAmbient) { s in
                s.add(2.5, part == .night, "ночное время")
                s.add(2.0, light == .dark, "очень тёмное помещение")
                s.add(1.0, light == .dim, "приглушённый свет")
                s.add(0.5, compact && indoor, "небольшое пространство")
            },
            match(.focus) { s in
                s.add(2.0, p.areas.table > 0.8, "есть рабочий стол")
                s.add(1.0, light == .normal || light == .bright, "хорошее освещение")
                s.add(1.0, tone != .warm, "нейтральный свет")
                s.add(0.5, (compact || size == .medium) && indoor, "камерный размер")
                s.add(1.0, part == .day || part == .morning, "рабочее время")
            },
            match(.cafeJazz) { s in
                s.add(1.5, p.areas.table > 0.5 && p.areas.seat > 0.5, "столы и сиденья")
                s.add(1.0, size == .medium, "средний размер")
                s.add(1.0, tone == .warm, "тёплое освещение")
                s.add(1.0, part == .evening || part == .day, "подходящее время суток")
            },
            match(.morningAcoustic) { s in
                s.add(2.0, part == .morning, "утро")
                s.add(1.5, light == .bright, "яркий свет")
                s.add(1.5, p.windowShare > 0.04, "много окон")
                s.add(0.5, tone != .warm, "дневной оттенок света")
            },
            match(.energy) { s in
                s.add(1.5, sparse, "мало мебели — много места")
                s.add(1.0, roomy, "просторно")
                s.add(1.0, light == .bright, "яркий свет")
                s.add(0.5, part == .day || part == .evening, "активное время суток")
            },
            match(.openAir) { s in
                s.add(4.0, p.isOutdoor, "открытое пространство")
                s.add(0.5, p.isOutdoor && tone != .warm, "дневной свет")
            },
            match(.cinematic) { s in
                s.add(3.0, size == .large || size == .huge, "большой объём")
                s.add(1.0, p.height > 3.5, "высокие потолки")
                s.add(0.5, light == .dim || light == .dark, "полумрак")
            }
        ]

        return all.enumerated()
            .sorted { l, r in
                l.element.score != r.element.score
                    ? l.element.score > r.element.score
                    : l.offset < r.offset
            }
            .map(\.element)
    }
}
