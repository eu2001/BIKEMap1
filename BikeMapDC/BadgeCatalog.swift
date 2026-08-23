import Foundation

// MARK: - Badge Catalog
//
// Friend-to-friend compliments for cyclists. Slugs are stable English
// identifiers stored in the `badges` table; the labels shown in the UI
// are in Portuguese (pt-BR) — a nod to the community's roots and the
// warmer feel of a compliment in your own language.

enum Badge: String, CaseIterable, Identifiable {
    case strongClimber      = "strong_climber"
    case speedDemon         = "speed_demon"
    case allWeather         = "all_weather"
    case communityHero      = "community_hero"
    case trailblazer        = "trailblazer"
    case rideBuddy          = "ride_buddy"
    case fixitWhiz          = "fixit_whiz"
    case centuryClub        = "century_club"
    case earlyBird          = "early_bird"
    case nightRider         = "night_rider"
    case safetyFirst        = "safety_first"
    case beginnerFriendly   = "beginner_friendly"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .strongClimber:    return "🚵"
        case .speedDemon:       return "⚡"
        case .allWeather:       return "🌧️"
        case .communityHero:    return "🌟"
        case .trailblazer:      return "🗺️"
        case .rideBuddy:        return "🤝"
        case .fixitWhiz:        return "🔧"
        case .centuryClub:      return "🏆"
        case .earlyBird:        return "🌅"
        case .nightRider:       return "🦉"
        case .safetyFirst:      return "🛡️"
        case .beginnerFriendly: return "💛"
        }
    }

    // Portuguese-BR label — this is what appears on the badge chip.
    var title: String {
        switch self {
        case .strongClimber:    return "Escalador de Aço"
        case .speedDemon:       return "Foguete"
        case .allWeather:       return "Guerreiro do Tempo"
        case .communityHero:    return "Herói da Comunidade"
        case .trailblazer:      return "Desbravador"
        case .rideBuddy:        return "Parceiro de Pedal"
        case .fixitWhiz:        return "Mão-Boa de Bike"
        case .centuryClub:      return "Clube dos 100 km"
        case .earlyBird:        return "Madrugador"
        case .nightRider:       return "Coruja Pedaleira"
        case .safetyFirst:      return "Cauteloso"
        case .beginnerFriendly: return "Acolhedor"
        }
    }

    // Portuguese-BR one-line description — what the badge is celebrating.
    var subtitle: String {
        switch self {
        case .strongClimber:    return "Sobe qualquer ladeira sem reclamar."
        case .speedDemon:       return "Rapidinho no pedal — pra tudo."
        case .allWeather:       return "Chuva, sol ou frio, sempre pedala."
        case .communityHero:    return "Ajuda a manter o mapa vivo."
        case .trailblazer:      return "Conhece todos os cantos e atalhos."
        case .rideBuddy:        return "Sempre disposto para uma rota."
        case .fixitWhiz:        return "Consertaria uma bike de olhos vendados."
        case .centuryClub:      return "Pedalou 100 km ou mais numa tacada só."
        case .earlyBird:        return "Pedalando antes do sol nascer."
        case .nightRider:       return "Não tem medo do escuro — luzes acesas."
        case .safetyFirst:      return "Capacete, luzes e respeito às regras."
        case .beginnerFriendly: return "Recebe iniciantes de coração aberto."
        }
    }

    static func fromSlug(_ slug: String) -> Badge? {
        Badge(rawValue: slug)
    }
}
