import Foundation
import MapKit
import SwiftUI

// MARK: - Infrastructure Types

enum InfraType: String, CaseIterable, Codable {
    case ciclovia, ciclofaixa, compartilhada, rota_alternativa, proibida, projetada, em_construcao

    var uiColor: UIColor {
        switch self {
        case .ciclovia:         return .init(red: 0.55, green: 0.00, blue: 0.00, alpha: 1) // dark red
        case .ciclofaixa:       return .init(red: 0.92, green: 0.30, blue: 0.30, alpha: 1) // light red
        case .compartilhada:    return .init(red: 0.45, green: 0.70, blue: 0.95, alpha: 1) // light blue
        case .rota_alternativa: return .init(red: 0.18, green: 0.65, blue: 0.35, alpha: 1) // green
        case .proibida:         return .init(red: 0.30, green: 0.30, blue: 0.30, alpha: 1) // dark grey
        case .projetada:        return .init(red: 0.976, green: 0.451, blue: 0.086, alpha: 1) // orange
        case .em_construcao:    return .init(red: 0.90, green: 0.70, blue: 0.00, alpha: 1) // yellow
        }
    }

    var color: Color { Color(uiColor) }

    var lineWidth: CGFloat {
        switch self {
        case .ciclovia:         return 5
        case .ciclofaixa:       return 4
        case .compartilhada:    return 3
        case .rota_alternativa: return 3
        case .proibida:         return 4
        case .projetada:        return 3
        case .em_construcao:    return 4
        }
    }

    var dashPattern: [NSNumber]? {
        switch self {
        case .ciclovia:         return nil
        case .ciclofaixa:       return nil
        case .compartilhada:    return nil
        case .rota_alternativa: return [8, 5]
        case .proibida:         return nil
        case .projetada:        return [10, 6]
        case .em_construcao:    return [4, 4]
        }
    }

    var label: String {
        switch self {
        case .ciclovia:         return "Ciclovia"
        case .ciclofaixa:       return "Ciclofaixa"
        case .compartilhada:    return "Via Compartilhada"
        case .rota_alternativa: return "Rota Alternativa"
        case .proibida:         return "Via Proibida"
        case .projetada:        return "Projetada"
        case .em_construcao:    return "Em Construção"
        }
    }
}

// MARK: - Infrastructure Feature

struct BikeInfraFeature {
    let name: String
    let type: InfraType
    let coordinates: [CLLocationCoordinate2D]
    let extensionKm: String?
    let reason: String?
    let status: String?
    let forecast: String?
}

// MARK: - POI Type

enum POIType: String, CaseIterable, Codable {
    case paraciclo, bike_sharing, loja, reparo, bomba, chuveiro, furto
    case acidente_ferido, acidente_morte

    var emoji: String {
        switch self {
        case .paraciclo:       return "🚲"
        case .loja:            return "🏪"
        case .reparo:          return "🔧"
        case .bomba:           return "💨"
        case .chuveiro:        return "🚿"
        case .acidente_ferido: return "⚠️"
        case .acidente_morte:  return "❌"
        case .bike_sharing:    return "🚴‍♂️"
        case .furto:           return "🔓"
        }
    }

    var label: String {
        switch self {
        case .paraciclo:       return "Paraciclo / Bicicletário"
        case .bike_sharing:    return "Estação de Bike Compartilhada"
        case .loja:            return "Loja de Bikes"
        case .reparo:          return "Pontos de Reparo"
        case .bomba:           return "Bombas de Ar"
        case .chuveiro:        return "Chuveiro / Vestiário"
        case .furto:           return "Furtos de Bicicleta"
        case .acidente_ferido: return "Acidentes com Ciclistas"
        case .acidente_morte:  return "Acidentes Fatais"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .paraciclo:       return .systemBlue
        case .loja:            return .init(red: 0.851, green: 0.467, blue: 0.039, alpha: 1)
        case .reparo:          return .init(red: 0.086, green: 0.639, blue: 0.255, alpha: 1)
        case .bomba:           return .init(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        case .chuveiro:        return .init(red: 0.031, green: 0.569, blue: 0.702, alpha: 1)
        case .acidente_ferido: return .init(red: 0.918, green: 0.702, blue: 0.000, alpha: 1)
        case .acidente_morte:  return .init(red: 0.863, green: 0.149, blue: 0.149, alpha: 1)
        case .bike_sharing:    return .init(red: 0.486, green: 0.227, blue: 0.933, alpha: 1)
        case .furto:           return .init(red: 0.294, green: 0.337, blue: 0.412, alpha: 1)
        }
    }

    var color: Color { Color(uiColor) }

    var canContribute: Bool {
        switch self {
        case .paraciclo, .loja, .reparo, .bomba, .chuveiro, .furto, .acidente_ferido: return true
        default: return false
        }
    }
}

// MARK: - POI

struct POI: Identifiable, Codable, Equatable {
    var id: String
    var type: String
    var lat: Double
    var lng: Double
    var title: String
    var description: String
    var author: String
    var createdAt: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var poiType: POIType { POIType(rawValue: type) ?? .paraciclo }
}


enum MapPickingMode {
    case addPoint
}

// MARK: - Custom MKPolyline

final class BikePolyline: MKPolyline {
    var infraType: InfraType = .ciclovia
    var featureName: String = ""
    var extensionKm: String?
    var reason: String?
    var status: String?
    var forecast: String?
}

// MARK: - POI Annotation

final class POIAnnotation: MKPointAnnotation {
    let poi: POI
    init(poi: POI) {
        self.poi = poi
        super.init()
        coordinate = poi.coordinate
        title = poi.title
    }
}

// MARK: - Avatar mapping

// MARK: - Avatar View

struct AvatarView: View {
    let id: String
    var size: CGFloat = 40

    var body: some View {
        Image(id)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 1))
    }
}

let avatarList: [(id: String, name: String)] = [
    ("tucano",   "Tucano"),
    ("capivara", "Capivara"),
    ("muiriqui", "Muriqui"),
    ("preguica", "Preguiça"),
    ("gamba",    "Gambá")
]
