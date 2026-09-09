import Foundation

// MARK: - 提示词库（「试试手气」/「试试手气 Pro」）
//
// Pro 为两阶段：
//   阶段 1 选句：qwen3.7-text-embedding-flash 把「目的种子」与候选句一起向量化，取语义最贴近的 top3 作参照
//   阶段 2 扩写：qwen-plus 按媒介定制的指令，把参照句 + 目的扩写成 ~500 字全新提示词（不复读原句）
// 词库分两层：结构化「词语/短语」维度（驱动扩写）+ 完整「整句」（供免费随机和选句参照）

/// 提示词类型：视频 / 图片 / 语音
enum PromptKind: String, CaseIterable {
    case video, image, audio

    var label: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        case .audio: return "语音"
        }
    }

    /// 阶段 2 的 max_tokens 上限（按媒介的预算护栏）
    var maxGenTokens: Int {
        switch self {
        case .image: return 800
        case .video: return 1100
        case .audio: return 1400
        }
    }
}

enum PromptBank {

    // MARK: - 结构化词库（维度 → 词语/短语）

    static let videoLexicon: [(dim: String, words: [String])] = [
        ("场景", ["雨夜街道", "废弃工厂", "雪山垭口", "深夜食堂", "热闹夜市",
                "无垠沙漠", "深海遗迹", "云端城市", "旧车站台", "竹林小径"]),
        ("主体", ["独行旅人", "机械蝴蝶", "老式吉普", "流浪的猫", "涂鸦少年",
                "拉面师傅", "登山者", "发光水母", "送信的鸟", "修钟老人"]),
        ("运镜", ["缓慢推近", "手持跟拍", "环绕运镜", "俯拍拉升", "长焦压缩",
                "低角度仰拍", "一镜到底", "航拍俯冲", "轨道横移", "定格特写"]),
        ("氛围感", ["孤独寂寥", "热血澎湃", "温柔治愈", "紧张悬疑", "史诗壮阔",
                 "慵懒日常", "怀旧胶片", "梦幻迷离", "静谧禅意", "荒诞幽默"]),
        ("声音氛围", ["雨声与闷雷", "机械嗡鸣", "柴火噼啪", "风声与呼吸", "远处汽笛",
                  "心跳低频", "蝉鸣鸟叫", "电子低频", "木门吱呀", "海浪拍岸"]),
        ("光影", ["霓虹湿地面反射", "逆光剪影", "烛火暖光", "晨雾漫射", "硬顶光",
                "月夜冷蓝", "金色黄昏", "频闪灯影", "百叶窗条纹光", "雪地反光"]),
    ]

    static let imageLexicon: [(dim: String, words: [String])] = [
        ("主体", ["柯基犬", "水乡小镇", "机械城堡", "玻璃花房", "老木桌",
                "宇航员", "云中鲸鱼", "纸飞机", "灯塔", "旧皮箱"]),
        ("风格", ["水彩", "赛博朋克", "极简主义", "宫崎骏", "8-bit 像素",
                "商业摄影", "超现实", "国风工笔", "蒸汽朋克", "胶片写实"]),
        ("构图", ["三分法", "中心对称", "大量留白", "低角度", "框架构图",
                "对角线", "俯视平铺", "特写微距", "黄金螺旋", "重复阵列"]),
        ("光线", ["暖色侧光", "清晨薄雾", "逆光光晕", "柔和窗光", "夜景灯海",
                "硬光投影", "体积光柱", "冷调月光", "烛光摇曳", "霓虹漫射"]),
        ("色彩", ["莫兰迪灰", "高饱和撞色", "紫绿幻彩", "黑白", "暖橙蓝对比",
                "粉彩", "金属冷灰", "大地色", "青橙调", "单色强调"]),
        ("细节", ["露珠", "颗粒质感", "发丝光泽", "布料纹理", "金属划痕",
                "纸张纤维", "光斑", "薄烟雾", "水波倒影", "剥落墙皮"]),
    ]

    static let audioLexicon: [(dim: String, words: [String])] = [
        ("语气", ["温柔低语", "沉稳播报", "轻快活泼", "深情独白", "冷静克制",
                "俏皮调侃", "磁性低音", "亲切邻家", "略带沙哑", "坚定有力"]),
        ("场景", ["深夜电台", "清晨问候", "旅途解说", "睡前故事", "产品介绍",
                "现场主持", "电话留言", "开幕致辞", "课堂讲解", "车站广播"]),
        ("节奏", ["缓慢悠长", "明快跳跃", "先缓后急", "停顿留白", "稳定均匀",
                "渐强推进", "循环往复", "短句利落", "一气呵成", "轻重交替"]),
        ("内容内核", ["回忆童年", "城市夜色", "生活小确幸", "探索未知", "人间烟火",
                  "季节更替", "孤独与陪伴", "告别与重逢", "慢下来的午后", "雨天的窗"]),
    ]

    static func lexicon(_ kind: PromptKind) -> [(dim: String, words: [String])] {
        switch kind {
        case .video: return videoLexicon
        case .image: return imageLexicon
        case .audio: return audioLexicon
        }
    }

    // MARK: - 完整整句（免费「试试手气」随机取用；也作为 Pro 选句候选）

    static let video: [String] = [
        "一个由喷漆画成的少年从混凝土墙上活过来，边 rap 边摆出充满活力的说唱姿势，夜晚铁路桥下，街灯孤照，电影感氛围。",
        "一只毛茸茸的小猫戴着宇航员头盔，漂浮在失重的空间站里，慢镜头，柔和灯光。",
        "雨夜霓虹都市，一名撑红伞的女子走过湿漉漉的街道，倒影斑斓，赛博朋克风格。",
        "俯拍视角，沙漠中一辆复古吉普扬尘飞驰，夕阳把沙丘染成金色，长焦压缩感。",
        "一间深夜食堂，热气腾腾的拉面，镜头缓缓推近，蒸汽在暖黄灯光下袅袅升起。",
        "海浪拍打礁石，海鸥掠过，慢动作水花四溅，清晨薄雾，电影感自然光。",
        "一只机械蝴蝶停在一朵盛开的金属花上，特写微距，齿轮转动，蒸汽朋克。",
        "雪山之巅，登山者插下旗帜，风吹雪雾，逆光剪影，史诗感构图。",
        "热闹的夜市摊档，铁板烧师傅翻炒食材，火焰腾起，升格慢镜头。",
        "清晨森林，一束阳光穿透树冠，光柱中尘埃飞舞，镜头缓缓上摇。",
    ]

    static let image: [String] = [
        "一只戴墨镜的柯基犬坐在海滩上，身边放着椰子，阳光明媚，插画风格。",
        "未来主义摩天楼群，悬浮列车穿梭，紫色与青色霓虹，赛博朋克城市。",
        "水彩画，宁静的江南水乡，白墙黛瓦，小桥流水，清晨薄雾。",
        "一只巨大的鲸鱼在云海中游弋，天空之城，梦幻超现实主义。",
        "特写：一杯拉花拿铁，木质桌面，暖色侧光，商业摄影质感。",
        "宫崎骏风格的田园小屋，绿草如茵，蓝天白云，远处风车转动。",
        "一只发光的水母在深海中漂浮，蓝色荧光，神秘幽深。",
        "像素风 8-bit 游戏场景，勇士站在城堡前，勇者斗恶龙。",
        "极简主义海报，一只红色气球飘向天空，大量留白，高级灰背景。",
        "冬日雪景，红色小木屋烟囱冒烟，松树挂雪，温馨童话感。",
    ]

    static let audio: [String] = [
        "夜色渐深，城市慢慢安静下来。远处的灯火一盏盏熄灭，只剩下风穿过树梢的声音。",
        "欢迎收听今天的节目。我们来聊一个有趣的话题：为什么有些人，天生就更乐观一点？",
        "先把米淘洗干净，加一小撮盐，再滴两滴油，这样煮出来的米饭粒粒分明，还带着光泽。",
        "风从海面上吹来，带着一点咸味。她站在礁石上，看着远处的灯塔，一闪，一闪。",
        "各位旅客您好，本次列车即将到达终点站，请您带好随身物品，准备下车。",
        "小时候，夏天的傍晚总是很长。蝉鸣、蒲扇、冰镇西瓜，还有外婆讲不完的故事。",
        "在这个快节奏的时代，能安静地读完一本书，已经变成了一种小小的奢侈。",
        "雨停了。空气里有泥土的味道，孩子们跑出家门，踩着水洼，笑声传得很远很远。",
        "亲爱的朋友，愿你今天遇到的每一件小事，都刚好合你的心意。晚安，好梦。",
        "他推开门，屋里的灯还亮着。桌上留着一张纸条：饭在锅里，记得热一热再吃。",
    ]

    // MARK: - 目的 / 主题种子

    static let purposeSeeds: [PromptKind: [String]] = {
        [
            .video: ["雨夜城市", "童年记忆", "孤独旅人", "机械与自然", "美食烟火", "深海雪原"],
            .image: ["静谧江南", "赛博都市", "暖色日常", "超现实梦境", "极简秩序", "荒野星光"],
            .audio: ["温柔晚安", "晨间问候", "旅途旁白", "深夜电台", "日常开场白", "季节随笔"],
        ]
    }()

    static func corpus(_ kind: PromptKind) -> [String] {
        switch kind {
        case .video: return video
        case .image: return image
        case .audio: return audio
        }
    }

    static func random(_ kind: PromptKind) -> String {
        let c = corpus(kind)
        return c.randomElement() ?? ""
    }

    // MARK: - 阶段 1：候选句（整句 + 词库随机组合句）

    static func comboSentence(_ kind: PromptKind) -> String {
        lexicon(kind).map { $0.words.randomElement() ?? "" }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// 本次向量化的文本：首条为种子，其余为候选句（接口单次 ≤ 20 条）
    static func plannedTexts(kind: PromptKind, purpose: String) -> [String] {
        let seed = effectiveSeed(kind: kind, purpose: purpose)
        var pool: [String] = corpus(kind).shuffled()
        for _ in 0..<8 { pool.append(comboSentence(kind)) }
        pool.shuffle()
        return [seed] + Array(pool.prefix(18))
    }

    static func effectiveSeed(kind: PromptKind, purpose: String) -> String {
        let t = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return purposeSeeds[kind]?.randomElement() ?? kind.label
    }

    // MARK: - 阶段 2：扩写指令

    static func systemInstruction(_ kind: PromptKind) -> String {
        let base = "你是资深创意文案与分镜脚本撰写人。只输出正文，不要标题、不要解释、不要复述或引用输入的原句。"
        switch kind {
        case .image:
            return base + "请输出一段约 500 字的中文文生图提示词，需覆盖：主体、构图、质感、风格、光线、景别、色彩、细节。语言具体、画面感强，可直接贴给文生图模型。"
        case .video:
            return base + "请输出一段约 500 字的中文视频提示词，需覆盖：场景、主体、运镜、分镜与转场、声音氛围、光影、节奏走向。语言具体、可执行，可直接贴给文生视频模型。"
        case .audio:
            return base + "请输出一段约 500 字、可直接朗读的中文解说/旁白文案（不是画面描述）。要求：口语化、句子短、有停顿节奏、情绪连贯，适合 TTS 朗读。"
        }
    }

    static func userPrompt(kind: PromptKind, seed: String, refs: [String]) -> String {
        var s = "创作目的/关键词：\(seed)\n\n可参考的素材（仅供风格与方向参考，禁止照抄原句）：\n"
        for (i, r) in refs.enumerated() { s += "\(i + 1). \(r)\n" }
        s += "\n请围绕「\(seed)」重新创作一段全新的内容："
        switch kind {
        case .audio:
            s += "一段可直接朗读的旁白/解说文案。"
        case .image:
            s += "一段可直接用于文生图的画面提示词。"
        case .video:
            s += "一段可直接用于文生视频的分镜化提示词。"
        }
        return s
    }

    // MARK: - Pro 主流程

    struct ProResult {
        let prompt: String
        let embedTokens: Int
        let genTokens: Int
        let usedPro: Bool
        let refs: [String]
        var totalTokens: Int { embedTokens + genTokens }
    }

    /// 两阶段：embedding 选 top3 参照句 → qwen-plus 扩写 ~500 字。任一阶段失败则降级为普通随机（不计费）
    @MainActor
    static func pro(kind: PromptKind, purpose: String = "") async -> ProResult {
        let texts = plannedTexts(kind: kind, purpose: purpose)
        let seed = effectiveSeed(kind: kind, purpose: purpose)
        let candidates = Array(texts.dropFirst())

        var refs: [String] = []
        var embedTokens = 0
        do {
            let (vecs, tokens) = try await DashScopeClient.shared.embed(texts: texts)
            embedTokens = tokens
            if vecs.count == texts.count, let q = vecs.first, !q.isEmpty {
                var scored: [(String, Double)] = []
                for (i, c) in candidates.enumerated() {
                    scored.append((c, cosine(q, vecs[i + 1])))
                }
                scored.sort { $0.1 > $1.1 }
                refs = Array(scored.prefix(3)).map { $0.0 }
            }
        } catch {
            return ProResult(prompt: random(kind), embedTokens: 0, genTokens: 0,
                             usedPro: false, refs: [])
        }
        if refs.isEmpty { refs = Array(candidates.prefix(3)) }

        do {
            let gen = try await DashScopeClient.shared.generateText(
                model: FixedModel.textGeneration,
                system: systemInstruction(kind),
                user: userPrompt(kind: kind, seed: seed, refs: refs),
                maxTokens: kind.maxGenTokens,
                temperature: 0.9)
            let text = gen.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return ProResult(prompt: random(kind), embedTokens: embedTokens, genTokens: 0,
                                 usedPro: false, refs: refs)
            }
            return ProResult(prompt: text, embedTokens: embedTokens, genTokens: gen.tokens,
                             usedPro: true, refs: refs)
        } catch {
            return ProResult(prompt: random(kind), embedTokens: embedTokens, genTokens: 0,
                             usedPro: false, refs: refs)
        }
    }

    /// 余弦相似度
    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let den = sqrt(na) * sqrt(nb)
        return den > 0 ? dot / den : 0
    }
}
