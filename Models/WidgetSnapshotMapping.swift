import Foundation

extension WidgetSnapshot {
    static func make(
        accountStatus: LocalAccountStatus,
        gachaRecords: [GachaRecord],
        gachaSummary: GachaSummary,
        plans: [CultivationPlan],
        generatedAt: Date = Date()
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: generatedAt,
            signIn: WidgetSignInSnapshot(status: accountStatus),
            gacha: WidgetGachaSnapshot(records: gachaRecords, summary: gachaSummary),
            planner: WidgetPlannerSnapshot(plans: plans)
        )
    }
}

extension WidgetSignInSnapshot {
    init(status: LocalAccountStatus) {
        guard status.isSignedIn else {
            self = .signedOut
            return
        }
        let isSigned = status.signInSummary?.isTodaySigned == true
        self.init(
            isSignedIn: true,
            nickname: status.nickname ?? status.selectedRole?.nickname,
            uid: status.signInSummary?.uid ?? status.selectedRole?.uid,
            isTodaySigned: isSigned,
            totalSignDay: status.signInSummary?.totalSignDay ?? 0,
            statusText: isSigned ? "已签到" : "待签到",
            actionTitle: isSigned ? "查看账号" : "去签到",
            message: status.sessionMessage
        )
    }
}

extension WidgetGachaSnapshot {
    init(records: [GachaRecord], summary: GachaSummary) {
        let newestFiveStar = records
            .filter { $0.rarity == 5 }
            .sorted { $0.time > $1.time }
            .first
        self.init(
            totalPulls: summary.totalPulls,
            fiveStarCount: summary.fiveStarCount,
            fourStarCount: summary.fourStarCount,
            pitySinceLastFiveStar: summary.pitySinceLastFiveStar,
            lastFiveStarName: newestFiveStar?.name ?? "暂无五星记录",
            lastFiveStarDate: newestFiveStar?.time,
            characterPulls: records.filter { $0.banner == .character || $0.banner == .characterEvent2 }.count,
            weaponPulls: records.filter { $0.banner == .weapon }.count,
            standardPulls: records.filter { $0.banner == .standard }.count
        )
    }
}

extension WidgetPlannerSnapshot {
    init(plans: [CultivationPlan]) {
        self.init(
            rows: plans
                .filter { $0.completion < 1 }
                .sorted { lhs, rhs in
                    if lhs.completion != rhs.completion {
                        return lhs.completion < rhs.completion
                    }
                    return lhs.targetName.localizedStandardCompare(rhs.targetName) == .orderedAscending
                }
                .prefix(2)
                .compactMap(WidgetPlannerRow.init(plan:))
        )
    }
}

extension WidgetPlannerRow {
    init?(plan: CultivationPlan) {
        guard let requirement = plan.requirements.first(where: { $0.remaining > 0 }) ?? plan.requirements.first else {
            return nil
        }
        self.init(
            id: plan.id,
            targetName: plan.targetName,
            materialName: requirement.materialName,
            owned: requirement.owned,
            required: requirement.required,
            completion: plan.completion
        )
    }
}
