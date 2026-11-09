import Foundation

struct BoundRoleListPayload: Codable, Equatable {
    var list: [BoundRolePayload]

    func genshinRoles(gameBiz: String = "hk4e_cn") -> [GenshinRole] {
        list.filter { $0.gameBiz == gameBiz }.enumerated().map { index, payload in
            GenshinRole(
                uid: payload.gameUid,
                region: payload.region,
                nickname: payload.nickname,
                level: payload.level,
                isSelected: index == 0
            )
        }
    }
}

struct BoundRolePayload: Codable, Equatable {
    var gameBiz: String
    var gameUid: String
    var region: String
    var nickname: String
    var level: Int

    enum CodingKeys: String, CodingKey {
        case gameBiz = "game_biz"
        case gameUid = "game_uid"
        case region
        case nickname
        case level
    }
}

struct MiHoYoBindingClient {
    var httpClient = HoYoHTTPClient()

    func loadGenshinRoles(secrets: AccountSecrets) async throws -> [GenshinRole] {
        if secrets.isHoYoLAB {
            let url = URL(string: "https://api-os-takumi.mihoyo.com/binding/api/getUserGameRolesByCookie?game_biz=hk4e_global")!
            let request = try HoYoLABAPI.request(url: url, secrets: secrets, signed: true)
            let response: HoYoResponse<BoundRoleListPayload> = try await httpClient.send(request)
            return try response.requireDataPreservingRetcode().genshinRoles(gameBiz: "hk4e_global")
        }
        guard let cookieToken = secrets.cookieToken, !cookieToken.isEmpty else {
            throw AccountSessionError.missingAccount
        }
        let url = URL(string: "https://api-takumi.mihoyo.com/binding/api/getUserGameRolesByCookie?game_biz=hk4e_cn")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(HoYoRequestSigner.cookieHeader(for: secrets, kind: .cookieToken), forHTTPHeaderField: "Cookie")
        let response: HoYoResponse<BoundRoleListPayload> = try await httpClient.send(request)
        return try response.requireData().genshinRoles()
    }
}
