import Foundation

/// The same deterministic local rules used before model integration.
/// This path never requests generation, performs network I/O or writes memory.
@MainActor
enum LocalCoachRules {
    static func workoutOutline(locale: Locale) -> String {
        if locale.identifier.hasPrefix("ar") {
            return "قائمة تخطيط محلية:\n1. راجع ملاحظات آخر تمرين واختر حركات مألوفة لك.\n2. قرر ما يناسب شعورك اليوم، بما في ذلك الراحة عند الحاجة.\n3. سجّل المجموعات والتكرارات والأوزان التي أكملتها فعلاً، واترك القيم غير المعروفة فارغة.\nلا يقترح التطبيق زيادة تلقائية في الأحمال ولا يحدد جاهزيتك الصحية."
        }
        return "Local planning checklist:\n1. Review your last workout notes and choose movements you already know.\n2. Decide what feels manageable today, including rest when needed.\n3. Log the sets, repetitions and weights you actually complete; leave unknown values blank.\nThe app does not make an automatic load increase or determine health readiness."
    }

    static func reply(to message: String, context: CoachContext, locale: Locale) -> String {
        if locale.identifier.hasPrefix("ar") {
            return arabicReply(to: message, context: context)
        }
        return englishReply(to: message, context: context)
    }

    private static func arabicReply(to message: String, context: CoachContext) -> String {
        let text = message.lowercased()
        if ["تعب", "نوم", "مرهق", "tired", "sleep", "exhausted"].contains(where: text.contains) {
            return "إذا كنت متعباً، اجعل الراحة أولوية اليوم. اختر حركة خفيفة تناسبك، واشرب الماء، وامنح نفسك وقتاً كافياً للنوم."
        }
        if ["تمرين", "تدريب", "رياضة", "workout", "train", "gym"].contains(where: text.contains) {
            return "اختر تمريناً بسيطاً يناسب طاقتك اليوم، وركّز على الحركة المتحكم بها. يمكنك تسجيل ما فعلته وكيف شعرت لمراجعته لاحقاً."
        }
        if ["طعام", "وجبة", "بروتين", "food", "meal", "protein"].contains(where: text.contains) {
            return "حافظ على وجبات متنوعة ومنتظمة، وسجّل ما تعرفه فعلاً عن الوجبة. لا تحتاج إلى تخمين القيم الغذائية المفقودة."
        }
        if ["تقدم", "كيف", "progress", "how am i", "doing"].contains(where: text.contains) {
            return "يمكن أن تساعدك سجلاتك على التأمل في أهدافك. الإرشاد دون اتصال لا يقيس التقدم البدني ولا يثبت تأثير أي عادة."
        }
        return "اختر خطوة صغيرة ومفيدة اليوم: تسجيل شعورك، أو وجبة تعرف تفاصيلها، أو نشاط بسيط يناسبك. يمكنك مراجعة سجلاتك لاحقاً دون افتراض نتائج غير مقاسة."
    }

    private static func englishReply(to message: String, context: CoachContext) -> String {
        let lowercasedMessage = message.lowercased()
        let goal = context.profile?.primaryGoal.rawValue.lowercased() ?? "your goals"

        if lowercasedMessage.contains("tired") || lowercasedMessage.contains("sleep") || lowercasedMessage.contains("exhausted") {
            return "If you feel tired, make recovery the priority today. Keep movement light, hydrate early, and treat sleep as the main workout tonight — it supports \(goal) long term."
        }

        if lowercasedMessage.contains("workout") || lowercasedMessage.contains("train") || lowercasedMessage.contains("gym") {
            return "For training today, aim for clean reps and controlled intensity toward \(goal). If your energy is below a 7/10, reduce volume before reducing consistency."
        }

        if lowercasedMessage.contains("food") || lowercasedMessage.contains("meal") || lowercasedMessage.contains("protein") {
            return "Keep nutrition simple: protein at each meal to fuel \(goal), colorful carbs around training, and enough water before you worry about perfect details."
        }

        if lowercasedMessage.contains("stuck") || lowercasedMessage.contains("motivation") || lowercasedMessage.contains("unmotivated") {
            return "When motivation is low, fall back to the smallest possible action that still moves \(goal) forward. Consistency beats intensity when you're in a dip."
        }

        if lowercasedMessage.contains("how am i") || lowercasedMessage.contains("progress") || lowercasedMessage.contains("doing") {
            let streakNote = context.currentStreak > 0 ? " You're on a \(context.currentStreak)-day streak — keep it going." : ""
            return "Your logs can help you reflect on \(goal).\(streakNote) Offline coaching cannot determine physical progress or a habit's effects."
        }

        if !context.summary.isEmpty {
            let streakNote = context.currentStreak > 5 ? " (you're on a \(context.currentStreak)-day streak — nice work)" : ""
            return "I hear you. Based on your recent context and \(goal)\(streakNote), choose the smallest useful action today: one good meal, one focused workout block, or one recovery habit."
        }

        return "I hear you. Pick one small next step that supports your \(goal) today, then make it easy enough to actually do."
    }
}
