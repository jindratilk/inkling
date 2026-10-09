import Foundation

/// The "why" behind every suggestion. Coach rules ship their own lesson from the
/// engine; Harper rules get a curated lesson here, a smart spelling diagnosis,
/// or a category-level fallback.
enum Lessons {
    static func lesson(for lint: Lint) -> Lesson {
        if let lesson = lint.lesson { return lesson }
        if lint.isSpelling { return SpellingInsight.lesson(original: lint.original, suggestion: lint.suggestions.first) }
        if let curated = curated[lint.rule] { return curated }
        return fallback(for: lint)
    }

    /// Lesson for a rule name (used in the progress view where no lint exists).
    static func lesson(forRule rule: String, description: String? = nil) -> Lesson? {
        if let entry = GrammarEngine.coachLessons.first(where: { $0.rule == rule }) { return entry.lesson }
        if rule == "SpellCheck" {
            return Lesson(
                title: "Spelling",
                explanation: "English spelling often doesn’t follow pronunciation. Watch double letters (necessary, address), silent letters (Wednesday, know) and “i before e except after c” (receive, believe).",
                wrong: ["recieve", "adress", "neccessary"],
                right: ["receive", "address", "necessary"]
            )
        }
        if let curated = curated[rule] { return curated }
        guard let description, !description.isEmpty else { return nil }
        return Lesson(title: humanize(rule), explanation: clean(description), wrong: [], right: [])
    }

    static func title(forRule rule: String) -> String {
        lesson(forRule: rule)?.title ?? humanize(rule)
    }

    static func humanize(_ rule: String) -> String {
        let base = rule.replacingOccurrences(of: "Coach.", with: "")
        var out = ""
        for (i, c) in base.enumerated() {
            if i > 0, c.isUppercase { out.append(" ") }
            out.append(c)
        }
        return out.prefix(1).uppercased() + out.dropFirst().lowercased()
    }

    static func clean(_ markdown: String) -> String {
        markdown.replacingOccurrences(of: "`", with: "“").replacingOccurrences(of: "**", with: "")
    }

    private static func fallback(for lint: Lint) -> Lesson {
        let explanation = lint.description.isEmpty ? categoryExplanation(lint.category) : clean(lint.description)
        return Lesson(title: humanize(lint.rule), explanation: explanation, wrong: [], right: [])
    }

    private static func categoryExplanation(_ category: IssueCategory) -> String {
        switch category {
        case .spelling: "This word looks misspelled."
        case .grammar: "This part of the sentence doesn’t follow standard English grammar."
        case .punctuation: "Punctuation and capital letters help the reader follow your sentence."
        case .wordChoice: "Native speakers usually phrase this differently."
        case .clarity: "This works, but a simpler version reads more clearly."
        case .tip: "A gentle heads-up — keep it if it’s what you meant."
        }
    }

    // MARK: curated Harper lessons

    static let curated: [String: Lesson] = [
        "AnA": Lesson(
            title: "a vs. an",
            explanation: "Choose by the first *sound*, not the first letter. Use “an” before a vowel sound and “a” before a consonant sound.",
            wrong: ["an big problem", "a hour", "an university"],
            right: ["a big problem", "an hour (silent h)", "a university (“yoo” sound)"]
        ),
        "RepeatedWords": Lesson(
            title: "Repeated word",
            explanation: "The same word appears twice in a row — usually a typing slip when editing a sentence.",
            wrong: ["the the invoice"], right: ["the invoice"]
        ),
        "SentenceCapitalization": Lesson(
            title: "Capital letter at the start",
            explanation: "Every sentence begins with a capital letter, even in quick messages if you want to look professional.",
            wrong: ["thanks. see you tomorrow."], right: ["Thanks. See you tomorrow."]
        ),
        "CapitalizePersonalPronouns": Lesson(
            title: "“I” is always capital",
            explanation: "The pronoun “I” is always written as a capital letter — in every position, and in contractions like I’m, I’ve, I’ll.",
            wrong: ["i think i’m late"], right: ["I think I’m late"]
        ),
        "TheirToThere": Lesson(
            title: "their / there / they’re",
            explanation: "There = place or “there is/are”. Their = belonging to them. They’re = they are.",
            wrong: ["Their is a problem."], right: ["There is a problem.", "Their car is red.", "They’re late."]
        ),
        "ThereToTheir": Lesson(
            title: "their / there / they’re",
            explanation: "Their = belonging to them (their house). There = a place or “there is”.",
            wrong: ["They forgot there keys."], right: ["They forgot their keys."]
        ),
        "TheirToTheyre": Lesson(
            title: "their vs. they’re",
            explanation: "They’re is short for “they are”. Their shows possession.",
            wrong: ["Their coming tomorrow."], right: ["They’re coming tomorrow."]
        ),
        "TheyreToTheir": Lesson(
            title: "they’re vs. their",
            explanation: "Their shows possession (their idea). They’re = they are.",
            wrong: ["It’s they’re idea."], right: ["It’s their idea."]
        ),
        "ItsContraction": Lesson(
            title: "its vs. it’s",
            explanation: "It’s = it is / it has. Its = belonging to it. If you can say “it is”, write “it’s”.",
            wrong: ["Its raining."], right: ["It’s raining.", "The company changed its logo."]
        ),
        "ItsPossessive": Lesson(
            title: "its vs. it’s",
            explanation: "For possession, use “its” without an apostrophe (like his, her). “It’s” always means “it is” or “it has”.",
            wrong: ["The app and it’s features."], right: ["The app and its features."]
        ),
        "PossessiveYour": Lesson(
            title: "your vs. you’re",
            explanation: "Your = belonging to you (your email). You’re = you are.",
            wrong: ["Thanks for you help."], right: ["Thanks for your help."]
        ),
        "PronounContraction": Lesson(
            title: "Contractions",
            explanation: "A contraction joins two words with an apostrophe: you’re = you are, it’s = it is, they’re = they are. Possessives (your, its, their) never take an apostrophe.",
            wrong: ["Your welcome."], right: ["You’re welcome."]
        ),
        "ThenThan": Lesson(
            title: "then vs. than",
            explanation: "Than compares (bigger than). Then is about time or sequence (first this, then that).",
            wrong: ["It’s better then before."], right: ["It’s better than before.", "Finish this, then call me."]
        ),
        "ThatThan": Lesson(
            title: "than in comparisons",
            explanation: "After a comparative (more, less, better, bigger…) English uses “than”.",
            wrong: ["more that ten"], right: ["more than ten"]
        ),
        "ModalOf": Lesson(
            title: "should have, not “should of”",
            explanation: "“Should’ve” sounds like “should of”, but it’s short for “should have”. Same for could have, would have, must have.",
            wrong: ["We should of checked."], right: ["We should have checked.", "We should’ve checked."]
        ),
        "OpenCompounds": Lesson(
            title: "Two words, not one",
            explanation: "Some phrases are always written as separate words: a lot, in fact, as well, each other, at least.",
            wrong: ["alot", "infact"], right: ["a lot", "in fact"]
        ),
        "LongSentences": Lesson(
            title: "Long sentence",
            explanation: "This sentence is long enough that readers may lose the thread. Try splitting it into two, or cutting a clause.",
            wrong: [], right: []
        ),
        "Spaces": Lesson(
            title: "Extra spaces",
            explanation: "Use one space between words and after punctuation.",
            wrong: ["Hello  world"], right: ["Hello world"]
        ),
        "UnclosedQuotes": Lesson(
            title: "Unclosed quote",
            explanation: "A quotation mark was opened but never closed.",
            wrong: ["He said “yes."], right: ["He said “yes.”"]
        ),
        "PronounInflectionBe": Lesson(
            title: "Subject–verb agreement (be)",
            explanation: "I am · you are · he/she/it is · we/they are. Match “be” to the subject.",
            wrong: ["He are late.", "They is ready."], right: ["He is late.", "They are ready."]
        ),
        "PronounVerbAgreement": Lesson(
            title: "Subject–verb agreement",
            explanation: "In the present simple, he/she/it takes -s: he works, she goes, it seems. I/you/we/they don’t.",
            wrong: ["She work here.", "He don’t know."], right: ["She works here.", "He doesn’t know."]
        ),
        "IAmAgreement": Lesson(
            title: "I am",
            explanation: "With “I”, the verb “be” is always “am” (I am, I’m, I was).",
            wrong: ["I is ready."], right: ["I am ready."]
        ),
        "DefiniteArticle": Lesson(
            title: "The article “the”",
            explanation: "Use “the” when both you and the reader know which specific thing you mean, or when there’s only one (the sun, the internet).",
            wrong: [], right: []
        ),
        "SomeWithoutArticle": Lesson(
            title: "Missing article",
            explanation: "Singular countable nouns need an article (a, an, the) or another determiner (my, this…).",
            wrong: ["I have question."], right: ["I have a question."]
        ),
        "DoubleNegative": Lesson(
            title: "Double negative",
            explanation: "Standard English uses one negative per clause. Use “any” after a negative verb.",
            wrong: ["I don’t have nothing."], right: ["I don’t have anything.", "I have nothing."]
        ),
        "Didnt": Lesson(
            title: "didn’t + base verb",
            explanation: "After didn’t, use the base form of the verb.",
            wrong: ["I didn’t knew."], right: ["I didn’t know."]
        ),
        "SubjunctiveWasToWere": Lesson(
            title: "If I were…",
            explanation: "For imaginary situations, formal English uses “were” for all subjects: If I were you…",
            wrong: ["If I was you, I’d go."], right: ["If I were you, I’d go."]
        ),
        "MassNouns": Lesson(
            title: "Uncountable nouns",
            explanation: "Some nouns can’t be counted and have no plural: information, advice, furniture, feedback.",
            wrong: ["many informations"], right: ["a lot of information"]
        ),
        "CommaFixes": Lesson(
            title: "Comma spacing",
            explanation: "In English, a comma sticks to the word before it and is followed by a space.",
            wrong: ["Hello ,world"], right: ["Hello, world"]
        ),
        "MergeWords": Lesson(
            title: "One word",
            explanation: "These two parts form a single English word.",
            wrong: ["any one knows", "can not"], right: ["anyone knows", "cannot"]
        ),
        "SplitWords": Lesson(
            title: "Missing space",
            explanation: "Two words were joined together. Add a space between them.",
            wrong: ["thankyou"], right: ["thank you"]
        ),
        "LetsConfusion": Lesson(
            title: "let’s vs. lets",
            explanation: "Let’s = let us (a suggestion: Let’s go). Lets = allows (She lets me drive).",
            wrong: ["Lets meet tomorrow."], right: ["Let’s meet tomorrow."]
        ),
        "QuiteQuiet": Lesson(
            title: "quite vs. quiet",
            explanation: "Quite = fairly, rather. Quiet = not loud.",
            wrong: ["It’s quiet good."], right: ["It’s quite good.", "The office is quiet."]
        ),
        "ToTwoToo": Lesson(
            title: "to / too / two",
            explanation: "To = direction or infinitive. Too = also / excessively. Two = 2.",
            wrong: ["It’s to late.", "Me to!"], right: ["It’s too late.", "Me too!"]
        ),
        "TooTo": Lesson(
            title: "to vs. too",
            explanation: "Too means “also” or “more than needed”. To shows direction or starts an infinitive.",
            wrong: ["I want too go."], right: ["I want to go."]
        ),
        "ToLoseTooLoose": Lesson(
            title: "lose vs. loose",
            explanation: "Lose (one o) = stop having / not win. Loose (two o’s) = not tight.",
            wrong: ["Don’t loose it."], right: ["Don’t lose it.", "These jeans are loose."]
        ),
        "WereWhere": Lesson(
            title: "were vs. where",
            explanation: "Were = past of “are”. Where = which place.",
            wrong: ["Were are you?"], right: ["Where are you?", "We were late."]
        ),
        "TheWhetherWeather": Lesson(
            title: "weather vs. whether",
            explanation: "Weather = rain, sun, etc. Whether = if.",
            wrong: ["I don’t know weather it works."], right: ["I don’t know whether it works."]
        ),
        "Everyday": Lesson(
            title: "every day vs. everyday",
            explanation: "Everyday (one word) is an adjective: everyday life. Every day (two words) means each day: I run every day.",
            wrong: ["I go there everyday."], right: ["I go there every day.", "an everyday problem"]
        ),
        "OfCourse": Lesson(
            title: "of course",
            explanation: "“Of course” is always two words.",
            wrong: ["ofcourse"], right: ["of course"]
        ),
        "InflectedVerbAfterTo": Lesson(
            title: "to + base verb",
            explanation: "After the infinitive “to”, use the base verb with no -s, -ed or -ing.",
            wrong: ["I want to goes.", "We need to discussed it."], right: ["I want to go.", "We need to discuss it."]
        ),
        "NeedToNoun": Lesson(
            title: "need to + verb",
            explanation: "“Need to” is followed by a verb. For a thing, drop “to”: I need a break.",
            wrong: ["I need to coffee."], right: ["I need coffee.", "I need to drink coffee."]
        ),
        "DidPast": Lesson(
            title: "did + base verb",
            explanation: "“Did” already marks the past, so the main verb is the base form.",
            wrong: ["Did you saw it?"], right: ["Did you see it?"]
        ),
        "Discuss": Lesson(
            title: "discuss (no “about”)",
            explanation: "“Discuss” takes a direct object: discuss the plan.",
            wrong: ["discuss about the plan"], right: ["discuss the plan"]
        ),
        "DoMistake": Lesson(
            title: "make a mistake",
            explanation: "In English, you make a mistake (never do).",
            wrong: ["I did a mistake."], right: ["I made a mistake."]
        ),
        "ProperNouns": Lesson(
            title: "Capitalise names",
            explanation: "Names of people, places, companies, languages and nationalities start with a capital letter.",
            wrong: ["english", "prague"], right: ["English", "Prague"]
        ),
        "WrongApostrophe": Lesson(
            title: "Apostrophe",
            explanation: "Use an apostrophe for contractions (don’t) and possession (Tom’s), never for plurals (two apples, not apple’s).",
            wrong: ["dont", "two apple’s"], right: ["don’t", "two apples"]
        ),
        "ExplanationMark": Lesson(
            title: "Exclamation mark",
            explanation: "The punctuation mark is spelled “exclamation”, from the verb “exclaim”.",
            wrong: ["explanation mark"], right: ["exclamation mark"]
        ),
        "CompoundSubjectI": Lesson(
            title: "“X and I” as a subject",
            explanation: "When you’re part of the subject, use “I” and put yourself last: Tom and I went. Use “me” as an object: He called Tom and me.",
            wrong: ["Me and Tom went."], right: ["Tom and I went."]
        ),
    ]
}

/// Explains *why* a word is misspelled by comparing it with the suggestion.
enum SpellingInsight {
    static func lesson(original: String, suggestion: String?) -> Lesson {
        guard let s = suggestion, !s.isEmpty else {
            return Lesson(
                title: "Unknown word",
                explanation: "This word isn’t in the English dictionary. If it’s a name, a brand or a word you use on purpose, add it to your dictionary and Inkling will remember it.",
                wrong: [], right: []
            )
        }
        let (title, explanation) = diagnose(original, s)
        return Lesson(title: title, explanation: explanation, wrong: [original], right: [s])
    }

    private static func diagnose(_ o: String, _ s: String) -> (String, String) {
        let ol = o.lowercased(), sl = s.lowercased()

        if ol == sl {
            return ("Capital letter", "In English, this word is always capitalised.")
        }
        if s.contains("'") || s.contains("’"), ol == sl.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "") {
            return ("Missing apostrophe", "Contractions need an apostrophe where letters were left out: don’t = do not, I’m = I am, can’t = cannot.")
        }
        if ol.count == sl.count, swapped(ol, sl) {
            if (ol.contains("ie") && sl.contains("ei")) || (ol.contains("ei") && sl.contains("ie")) {
                return ("ie or ei?", "Remember: “i before e, except after c” — believe, friend, but receive, ceiling.")
            }
            return ("Swapped letters", "Two neighbouring letters are swapped — a classic fast-typing slip.")
        }
        if let diff = singleDifference(ol, sl) {
            switch diff {
            case let .missing(ch):
                if let prev = prevChar(of: sl, missing: ch), prev == ch {
                    return ("Double letter", "This word doubles the “\(ch)”. English often doubles consonants after a short vowel: address, necessary (1 c, 2 s), recommend (1 c, 2 m).")
                }
                if "hkwbet".contains(ch) {
                    return ("Silent letter", "This word has a silent “\(ch)” you don’t hear when you say it.")
                }
                return ("Missing letter", "A letter is missing: “\(ch)”.")
            case let .extra(ch):
                if let prev = prevChar(of: ol, missing: ch), prev == ch {
                    return ("Single letter", "This word has only one “\(ch)”, not two.")
                }
                return ("Extra letter", "There’s an extra “\(ch)” here.")
            case let .replaced(a, b):
                if (a == "v" && b == "w") || (a == "w" && b == "v") {
                    return ("v or w?", "English distinguishes “v” and “w” sounds — this word uses “\(b)”.")
                }
                if (a == "s" && b == "c") || (a == "c" && b == "s") || (a == "k" && b == "c") || (a == "c" && b == "k") {
                    return ("Same sound, different letter", "English often spells the same sound different ways (c/k/s). This word uses “\(b)”.")
                }
                if "aeiou".contains(a) && "aeiou".contains(b) {
                    return ("Vowel", "Unstressed English vowels all sound alike, so it’s easy to pick the wrong one. This word uses “\(b)”.")
                }
                return ("Spelling", "One letter is different: “\(a)” should be “\(b)”.")
            }
        }
        return ("Spelling", "This word isn’t spelled the usual way. Did you mean “\(s)”?")
    }

    private enum Diff { case missing(Character), extra(Character), replaced(Character, Character) }

    private static func swapped(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        let diffs = x.indices.filter { x[$0] != y[$0] }
        return diffs.count == 2 && diffs[1] == diffs[0] + 1 && x[diffs[0]] == y[diffs[1]] && x[diffs[1]] == y[diffs[0]]
    }

    private static func singleDifference(_ a: String, _ b: String) -> Diff? {
        let x = Array(a), y = Array(b)
        if x.count == y.count {
            let diffs = x.indices.filter { x[$0] != y[$0] }
            if diffs.count == 1 { return .replaced(x[diffs[0]], y[diffs[0]]) }
            return nil
        }
        if y.count == x.count + 1 {
            for i in y.indices where Array(y[..<i] + y[(i + 1)...]) == x { return .missing(y[i]) }
        }
        if x.count == y.count + 1 {
            for i in x.indices where Array(x[..<i] + x[(i + 1)...]) == y { return .extra(x[i]) }
        }
        return nil
    }

    /// Whether the given char appears doubled in `word` (signals a double-letter issue).
    private static func prevChar(of word: String, missing ch: Character) -> Character? {
        let w = Array(word)
        for i in 1..<max(1, w.count) where w[i] == ch && w[i - 1] == ch { return ch }
        return nil
    }
}
