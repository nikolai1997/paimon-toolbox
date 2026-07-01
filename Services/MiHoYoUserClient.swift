import Foundation

protocol MiHoYoUserProfileLoading: Sendable {
    func loadUserProfile(accountID: String) async throws -> MiHoYoUserProfile
}

struct MiHoYoUserProfile: Equatable {
    var nickname: String?
    var avatarURL: URL?
}

struct MiHoYoUserFullInfoPayload: Codable, Equatable {
    var userInfo: MiHoYoUserInfoPayload

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
    }
}

struct MiHoYoUserInfoPayload: Codable, Equatable {
    var uid: String?
    var nickname: String?
    var avatar: String?
    var avatarURL: URL?
    var avatarExtend: MiHoYoAvatarExtendPayload?

    var resolvedAvatarURL: URL? {
        if let avatarURL = avatarExtend?.preferredAvatarURL {
            return avatarURL
        }
        if let avatarURL {
            return avatarURL
        }
        guard let avatar, !avatar.isEmpty else {
            return nil
        }
        return URL(string: "https://bbs-static.miyoushe.com/avatar/avatar\(avatar).png")
    }

    enum CodingKeys: String, CodingKey {
        case uid
        case nickname
        case avatar
        case avatarURL = "avatar_url"
        case avatarExtend = "avatar_ext"
    }
}

struct MiHoYoAvatarExtendPayload: Codable, Equatable {
    var avatarType: String?
    var hdResources: [MiHoYoAvatarResourcePayload]

    var preferredAvatarURL: URL? {
        guard let avatarType else {
            return hdResources.first?.url
        }
        return hdResources.first { $0.format == avatarType }?.url ?? hdResources.first?.url
    }

    enum CodingKeys: String, CodingKey {
        case avatarType = "avatar_type"
        case hdResources = "hd_resources"
    }
}

struct MiHoYoAvatarResourcePayload: Codable, Equatable {
    var format: String?
    var url: URL?
}

struct MiHoYoUserClient: MiHoYoUserProfileLoading {
    var httpClient = HoYoHTTPClient()

    func loadUserProfile(accountID: String) async throws -> MiHoYoUserProfile {
        var components = URLComponents(string: "https://bbs-api.mihoyo.com/user/wapi/getUserFullInfo")!
        components.queryItems = [
            URLQueryItem(name: "uid", value: accountID),
            URLQueryItem(name: "gids", value: "2")
        ]
        guard let url = components.url else {
            throw AccountSessionError.invalidResponse("米游社用户资料地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HoYoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://bbs.mihoyo.com/", forHTTPHeaderField: "Referer")

        let response: HoYoResponse<MiHoYoUserFullInfoPayload> = try await httpClient.send(request)
        let userInfo = try response.requireData().userInfo
        return MiHoYoUserProfile(
            nickname: userInfo.nickname,
            avatarURL: userInfo.resolvedAvatarURL
        )
    }
}
