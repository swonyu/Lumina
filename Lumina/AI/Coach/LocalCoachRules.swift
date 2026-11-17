import Foundation

/// Deterministic help with the local journal. This path does not determine
/// health readiness, prescribe exercise/nutrition, perform network I/O or save records.
@MainActor
enum LocalCoachRules {
    static func workoutOutline(locale: Locale) -> String {
        if locale.identifier.hasPrefix("ar") {
            return "قائمة تخطيط محلية:\n1. راجع ملاحظات آخر تمرين واختر حركات مألوفة لك.\n2. قرر ما يناسب شعورك اليوم، بما في ذلك الراحة عند الحاجة.\n3. سجّل المجموعات والتكرارات والأوزان التي أكملتها فعلاً، واترك القيم غير المعروفة فارغة.\nلا يقترح التطبيق زيادة تلقائية في الأحمال ولا يحدد جاهزيتك الصحية."
        }
        return "Local planning checklist:\n1. Review your last workout notes and choose movements you already know.\n2. Decide what feels manageable today, including rest when needed.\n3. Log the sets, repetitions and weights you actually complete; leave unknown values blank.\nThe app does not make an automatic load increase or determine health readiness."
    }

    /// Conservative routing for recognized symptom/medical language, not a
    /// symptom checker. Conditional wording is intentional: keyword matches
    /// cannot establish that a symptom is present now, including negated or past mentions.
    static func safetyNotice(for message: String, locale: Locale) -> String? {
        let text = routingText(message)
        let words = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let medicalWords: Set<String> = [
            "pain", "pains", "painful", "hurt", "hurts", "injury", "injuries", "injured",
            "illness", "symptom", "symptoms", "diagnose", "diagnosis", "medication",
            "medications", "medicine", "medicines", "dosage", "dose", "doses",
            "dizzy", "dizziness", "faint", "fainting", "nausea", "bleeding", "diabetes",
            "pregnant", "pregnancy", "asthma",
            "الم", "الالم", "الام", "بالم", "بالالم", "بالام", "الما", "وجع",
            "يوجعني", "يولمني", "تولمني", "دوخه", "اغماء", "الاغماء",
            "نزيف", "غثيان", "اصابه", "الاصابه", "مصاب", "مرض", "المرض", "اعراض",
            "الاعراض", "تشخيص", "دواء", "الدواء", "ادويه", "الادويه", "جرعه",
            "الجرعه", "سكري", "السكري", "حامل", "الحمل", "ربو", "الربو"
        ]
        let mentionsChest = !words.isDisjoint(with: ["chest", "صدر", "الصدر", "صدري", "بالصدر", "بصدري"])
        let chestDiscomfort = mentionsChest && !words.isDisjoint(with: [
            "pain", "pains", "hurt", "hurts", "pressure", "tightness", "discomfort",
            "الم", "الالم", "الام", "بالم", "بالالم", "بالام", "الما",
            "وجع", "يوجعني", "يولمني", "تولمني", "ضغط", "ضيق"
        ])
        let breathingConcern = ["short of breath", "difficulty breathing", "trouble breathing",
            "cannot breathe", "can't breathe", "cant breathe", "ضيق في التنفس",
            "صعوبه في التنفس", "لا استطيع التنفس"].contains(where: text.contains)
        guard !words.isDisjoint(with: medicalWords) || chestDiscomfort || breathingConcern else { return nil }

        let urgentContext = chestDiscomfort || breathingConcern
            || !words.isDisjoint(with: ["faint", "fainting", "اغماء", "الاغماء"])
        if locale.identifier.hasPrefix("ar") {
            let boundary = "يمكنني مساعدتك في تدوين ما حدث، لكن لا يمكنني تقييم الأعراض أو تشخيص حالة صحية أو تحديد ما إذا كان التمرين أو تغيير النظام الغذائي أو الدواء آمناً لك."
            if urgentContext {
                return boundary + "\nإذا كان لديك الآن ألم في الصدر مع دوخة أو شعور بالإغماء أو صعوبة في التنفس، أو ألم مفاجئ في الصدر لا يزول، أو صعوبة شديدة في التنفس، فاطلب مساعدة طارئة فوراً من خدمات الطوارئ المحلية. ذكر أعراض سابقة أو غير موجودة الآن لا يعني وحده وجود حالة طارئة. اسأل مختصاً صحياً مؤهلاً عن الأعراض أو العلاج."
            }
            return boundary + " اسأل مختصاً صحياً مؤهلاً عن الأعراض أو العلاج. يمكنك تسجيل ملاحظاتك وتواريخها دون اعتبار هذا الرد تقييماً صحياً."
        }
        let boundary = "I can help you record what happened, but I cannot assess symptoms, diagnose a condition, or decide whether exercise, a diet change or medicine is safe for you."
        if urgentContext {
            return boundary + "\nIf you currently have chest pain with dizziness, faintness or breathing difficulty, sudden chest pain that does not go away, or severe breathing difficulty, seek immediate help from your local emergency services. Mentioning past or absent symptoms does not by itself establish an emergency. Ask a qualified health professional about symptoms or treatment."
        }
        return boundary + " Ask a qualified health professional about symptoms or treatment. You can record your observations and their dates without treating this reply as a health assessment."
    }

    static func reply(to message: String, context: CoachContext, locale: Locale) -> String {
        // Compatibility callers must not bypass the same medical boundary.
        if let notice = safetyNotice(for: message, locale: locale) { return notice }
        if locale.identifier.hasPrefix("ar") {
            return arabicReply(to: message, context: context)
        }
        return englishReply(to: message, context: context)
    }

    /// Bound work before the model's existing length guard. This includes every
    /// admitted model question (<=1600 UTF-8 bytes). A longer unmatched question
    /// receives only neutral journal help; no exercise/diet advice is a fallback.
    private static func routingText(_ message: String) -> String {
        let folded = CoachModelRequest.prefix(message, maximumUTF8Bytes: 16_384)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ـ", with: "")

        // Foundation folding preserves Arabic harakat on the supported Apple
        // runtime. Remove only these vowel/gemination marks from this bounded
        // routing copy; keep the original question and token boundaries intact.
        let routingScalars = folded.unicodeScalars.filter {
            !(0x064B...0x0652).contains($0.value)
        }
        return String(String.UnicodeScalarView(routingScalars))
    }

    private static func arabicReply(to message: String, context: CoachContext) -> String {
        let text = routingText(message)
        if ["تعب", "نوم", "مرهق", "tired", "sleep", "exhausted"].contains(where: text.contains) {
            return "يمكنك تسجيل شعورك في تسجيل يومي أو ملاحظة، ومراجعة تواريخ ملاحظاتك السابقة. لا يقيّم هذا الرد المحلي التعب أو التعافي أو الجاهزية للتمرين."
        }
        if ["تمرين", "تدريب", "رياضه", "workout", "train", "gym"].contains(where: text.contains) {
            return "يمكنك مراجعة سجلاتك في التمارين وتسجيل تمرين أكملته بالفعل. أدخل المجموعات والتكرارات والأوزان التي تعرفها، واترك القيم غير المعروفة فارغة. لا يحدد هذا الرد المحلي ما إذا كان عليك التمرين أو شدة تدريبك."
        }
        if ["طعام", "وجبه", "بروتين", "food", "meal", "protein"].contains(where: text.contains) {
            return "يمكنك تسجيل وجبة في التغذية. أدخل التفاصيل التي تعرفها واترك العناصر الغذائية غير المعروفة فارغة. القيم المحفوظة هي سجلاتك وليست وصفة غذائية."
        }
        if ["تقدم", "كيف", "progress", "how am i", "doing"].contains(where: text.contains) {
            return "يمكن أن تساعدك سجلاتك على التأمل في أهدافك. الإرشاد دون اتصال لا يقيس التقدم البدني ولا يثبت تأثير أي عادة."
        }
        return "يمكنك مراجعة سجلاتك المحفوظة أو إضافة سجل في الرئيسية أو التمارين أو التغذية أو التقدم. لا يقيس هذا الرد المحلي صحتك ولا يحفظ أي تغييرات نيابة عنك."
    }

    private static func englishReply(to message: String, context: CoachContext) -> String {
        let text = routingText(message)
        let goal = context.profile?.primaryGoal.rawValue.lowercased() ?? "your goals"
        if ["tired", "sleep", "exhausted"].contains(where: text.contains) {
            return "You can record how you feel in a check-in or journal entry and review the dates of earlier notes. This local reply cannot assess tiredness, recovery or readiness for exercise."
        }
        if ["workout", "train", "gym"].contains(where: text.contains) {
            return "You can review your saved workouts in Workouts and record a workout you have already completed. Enter the sets, repetitions and weights you know, and leave unknown values blank. This local reply does not decide whether to exercise or set your training intensity."
        }
        if ["food", "meal", "protein"].contains(where: text.contains) {
            return "You can record a meal in Nutrition. Enter the details you know and leave unknown nutrients blank. Saved values are your records, not a diet prescription."
        }
        if ["stuck", "motivation", "unmotivated"].contains(where: text.contains) {
            return "A small journal task can be enough: review a saved entry or record something you already completed. This local reply does not set a health or training target."
        }
        if ["how am i", "progress", "doing"].contains(where: text.contains) {
            let streakNote = context.currentStreak > 0 ? " You're on a \(context.currentStreak)-day streak — keep it going." : ""
            return "Your logs can help you reflect on \(goal).\(streakNote) Offline coaching cannot determine physical progress or a habit's effects."
        }
        return "You can review your saved logs or add a record in Home, Workouts, Nutrition or Progress. This local reply cannot measure your health or save changes for you."
    }
}
