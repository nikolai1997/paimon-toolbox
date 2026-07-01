import Foundation

struct GlobalSearchResult: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var section: AppSection
    var systemImage: String
    var searchableText: String
}

enum GlobalSearchIndex {
    static func results(
        matching query: String,
        metadata: MetadataBundle?,
        gachaRecords: [GachaRecord],
        plans: [CultivationPlan]
    ) -> [GlobalSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return entries(metadata: metadata, gachaRecords: gachaRecords, plans: plans)
            .filter { $0.searchableText.localizedStandardContains(normalizedQuery) }
    }

    private static func entries(
        metadata: MetadataBundle?,
        gachaRecords: [GachaRecord],
        plans: [CultivationPlan]
    ) -> [GlobalSearchResult] {
        var results = staticInterfaceEntries()

        if let metadata {
            results.append(contentsOf: metadata.characters.map { character in
                GlobalSearchResult(
                    id: "character-\(character.id)",
                    title: character.name,
                    subtitle: "角色 · \(character.element) · \(character.weaponType) · \(character.region)",
                    section: .database,
                    systemImage: "person.crop.square",
                    searchableText: [
                        character.name,
                        character.element,
                        character.weaponType,
                        character.region,
                        "\(character.rarity) 星",
                        character.materials.joined(separator: " ")
                    ].joined(separator: " ")
                )
            })

            results.append(contentsOf: metadata.weapons.map { weapon in
                GlobalSearchResult(
                    id: "weapon-\(weapon.id)",
                    title: weapon.name,
                    subtitle: "武器 · \(weapon.type) · \(weapon.stat)",
                    section: .database,
                    systemImage: "wand.and.stars",
                    searchableText: [
                        weapon.name,
                        weapon.type,
                        weapon.stat,
                        "\(weapon.rarity) 星",
                        weapon.materials.joined(separator: " ")
                    ].joined(separator: " ")
                )
            })

            results.append(contentsOf: metadata.materials.map { material in
                GlobalSearchResult(
                    id: "material-\(material.id)",
                    title: material.name,
                    subtitle: "材料 · \(material.category) · \(material.source)",
                    section: .database,
                    systemImage: "shippingbox",
                    searchableText: [
                        material.name,
                        material.category,
                        material.source
                    ].joined(separator: " ")
                )
            })
        }

        results.append(contentsOf: gachaRecords.map { record in
            GlobalSearchResult(
                id: "gacha-\(record.id)",
                title: record.name,
                subtitle: "祈愿记录 · \(record.banner.title) · \(record.itemType) · \(record.rarity) 星",
                section: .gachaLog,
                systemImage: "sparkles",
                searchableText: [
                    record.name,
                    record.banner.title,
                    record.itemType,
                    "\(record.rarity) 星"
                ].joined(separator: " ")
            )
        })

        results.append(contentsOf: plans.map { plan in
            GlobalSearchResult(
                id: "plan-\(plan.id.uuidString)",
                title: plan.targetName,
                subtitle: "养成计划 · \(plan.targetKind) · \(plan.currentLevel) -> \(plan.targetLevel)",
                section: .planner,
                systemImage: "checklist",
                searchableText: [
                    plan.targetName,
                    plan.targetKind,
                    "\(plan.currentLevel)",
                    "\(plan.targetLevel)",
                    plan.requirements.map(\.materialName).joined(separator: " ")
                ].joined(separator: " ")
            )
        })

        return results
    }

    private static func staticInterfaceEntries() -> [GlobalSearchResult] {
        [
            entry(.overview, "总览", "本地优先工具箱，资料来源，角色，武器，祈愿记录，养成计划"),
            entry(.database, "资料库", "资料类型，角色，武器，材料，元素，地区，突破材料"),
            entry(.gachaLog, "祈愿记录", "总抽数，五星，四星，当前垫数，导入，导出 UIGF"),
            entry(.planner, "养成规划", "调整材料数量，恢复样例，剩余，进度"),
            entry(.account, "账号与签到", "米游社扫码登录，扫码登录，立即签到，刷新，退出，启动后每天自动签到"),
            entry(.settings, "静态资源", "启动时自动从 GitHub 更新，刷新资料库缓存，内置数据源"),
            entry(.settings, "离线资料包", "网盘 data-pack.zip 分享链接，打开网盘下载链接，导入 data-pack.zip"),
            entry(.settings, "隐私声明", "本应用仅在本机处理账号凭据、抽卡记录和养成计划，不会主动上传个人数据")
        ]
    }

    private static func entry(_ section: AppSection, _ title: String, _ terms: String) -> GlobalSearchResult {
        GlobalSearchResult(
            id: "interface-\(section.rawValue)-\(title)",
            title: title,
            subtitle: "\(section.title) · 功能入口",
            section: section,
            systemImage: section.systemImage,
            searchableText: "\(section.title) \(title) \(terms)"
        )
    }
}
