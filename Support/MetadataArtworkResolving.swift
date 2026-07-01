import Foundation

extension GameCharacter {
    var inspectorArtworkURL: URL? {
        iconURL ?? portraitURL
    }
}
