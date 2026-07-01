import Foundation

#if !SWIFT_PACKAGE
extension Bundle {
    static var module: Bundle {
        .main
    }
}
#endif
