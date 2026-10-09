//! The Coach: hand-written rules for common English learner mistakes.
//! Each rule carries a small lesson so the app can teach, not just fix.

use regex::{Captures, Regex};
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Lesson {
    pub title: String,
    pub explanation: String,
    pub wrong: Vec<String>,
    pub right: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct CoachLint {
    pub rule: String,
    pub kind: &'static str,
    pub byte_start: usize,
    pub byte_end: usize,
    pub message: String,
    pub suggestions: Vec<String>,
    pub lesson: Lesson,
    pub hint: bool,
}

type FixFn = fn(&Captures) -> Vec<String>;

enum Fix {
    /// `${n}`-style templates expanded against the captures.
    Templates(&'static [&'static str]),
    Func(FixFn),
}

struct LessonDef {
    title: &'static str,
    explanation: &'static str,
    wrong: &'static [&'static str],
    right: &'static [&'static str],
}

struct RuleDef {
    id: &'static str,
    kind: &'static str,
    hint: bool,
    pattern: &'static str,
    /// Capture group that gets underlined & replaced (0 = whole match).
    target: usize,
    fix: Fix,
    message: &'static str,
    lesson: LessonDef,
    /// Reject the match if the text right after it matches this (anchored).
    not_followed: Option<&'static str>,
    /// Require the text right after the match to match this (anchored).
    must_follow: Option<&'static str>,
    /// Reject the match if the text right before it matches this (anchored at end).
    not_preceded: Option<&'static str>,
}

struct Rule {
    def: &'static RuleDef,
    regex: Regex,
    not_followed: Option<Regex>,
    must_follow: Option<Regex>,
    not_preceded: Option<Regex>,
}

pub struct Coach {
    rules: Vec<Rule>,
}

impl Coach {
    pub fn new() -> Self {
        let ci = |p: &str| Regex::new(&format!("(?i){p}")).expect("valid coach regex");
        let rules = RULES
            .iter()
            .map(|def| Rule {
                def,
                regex: ci(def.pattern),
                not_followed: def.not_followed.map(|p| ci(&format!("^(?:{p})"))),
                must_follow: def.must_follow.map(|p| ci(&format!("^(?:{p})"))),
                not_preceded: def.not_preceded.map(|p| ci(&format!("(?:{p})$"))),
            })
            .collect();
        Self { rules }
    }

    pub fn check(&self, text: &str) -> Vec<CoachLint> {
        let mut out: Vec<CoachLint> = Vec::new();
        for rule in &self.rules {
            let d = rule.def;
            for caps in rule.regex.captures_iter(text) {
                let whole = caps.get(0).unwrap();
                let after = &text[whole.end()..];
                let before = &text[..whole.start()];
                if rule.not_followed.as_ref().is_some_and(|r| r.is_match(after)) {
                    continue;
                }
                if rule.must_follow.as_ref().is_some_and(|r| !r.is_match(after)) {
                    continue;
                }
                if rule.not_preceded.as_ref().is_some_and(|r| r.is_match(before)) {
                    continue;
                }
                let Some(target) = caps.get(d.target) else { continue };
                if target.as_str().trim().is_empty() {
                    continue;
                }
                let original = target.as_str();
                let mut suggestions: Vec<String> = match &d.fix {
                    Fix::Templates(ts) => ts
                        .iter()
                        .map(|t| {
                            let mut s = String::new();
                            caps.expand(t, &mut s);
                            collapse_spaces(&s)
                        })
                        .collect(),
                    Fix::Func(f) => f(&caps),
                };
                suggestions = suggestions
                    .into_iter()
                    .map(|s| match_case(original, &s))
                    .filter(|s| s != original)
                    .collect();
                suggestions.dedup();

                if out.iter().any(|o| o.byte_start < target.end() && target.start() < o.byte_end) {
                    continue;
                }

                let fix = suggestions.first().cloned().unwrap_or_default();
                out.push(CoachLint {
                    rule: format!("Coach.{}", d.id),
                    kind: d.kind,
                    byte_start: target.start(),
                    byte_end: target.end(),
                    message: d.message.replace("{orig}", original).replace("{fix}", &fix),
                    suggestions,
                    lesson: Lesson {
                        title: d.lesson.title.to_string(),
                        explanation: d.lesson.explanation.to_string(),
                        wrong: d.lesson.wrong.iter().map(|s| s.to_string()).collect(),
                        right: d.lesson.right.iter().map(|s| s.to_string()).collect(),
                    },
                    hint: d.hint,
                });
            }
        }
        out.sort_by_key(|l| l.byte_start);
        out
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LessonEntry {
    pub rule: String,
    pub kind: &'static str,
    pub lesson: Lesson,
}

/// Every coach lesson, for the in-app lesson library.
pub fn all_lessons() -> Vec<LessonEntry> {
    RULES
        .iter()
        .map(|d| LessonEntry {
            rule: format!("Coach.{}", d.id),
            kind: d.kind,
            lesson: Lesson {
                title: d.lesson.title.to_string(),
                explanation: d.lesson.explanation.to_string(),
                wrong: d.lesson.wrong.iter().map(|s| s.to_string()).collect(),
                right: d.lesson.right.iter().map(|s| s.to_string()).collect(),
            },
        })
        .collect()
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn collapse_spaces(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut prev_space = false;
    for c in s.chars() {
        if c == ' ' {
            if !prev_space {
                out.push(c);
            }
            prev_space = true;
        } else {
            out.push(c);
            prev_space = false;
        }
    }
    out.trim().to_string()
}

/// Keep sentence-initial capitalisation of the original.
fn match_case(original: &str, suggestion: &str) -> String {
    let orig_upper = original.chars().next().is_some_and(|c| c.is_uppercase());
    let all_upper = original.len() > 3 && original.chars().all(|c| !c.is_lowercase());
    if all_upper {
        return suggestion.to_uppercase();
    }
    let mut chars = suggestion.chars();
    match chars.next() {
        Some(first) if orig_upper => first.to_uppercase().collect::<String>() + chars.as_str(),
        Some(first) if !orig_upper && first.is_uppercase() && !suggestion.starts_with("I ") && !suggestion.starts_with("I'") => {
            // Only lowercase if the original was lowercase and the template
            // capitalised a common word by accident.
            first.to_string() + chars.as_str()
        }
        _ => suggestion.to_string(),
    }
}

fn g<'a>(c: &'a Captures, i: usize) -> &'a str {
    c.get(i).map(|m| m.as_str()).unwrap_or("")
}

fn lower(c: &Captures, i: usize) -> String {
    g(c, i).to_lowercase()
}

fn base_form(past: &str) -> Option<&'static str> {
    Some(match past {
        "went" | "gone" => "go",
        "saw" | "seen" => "see",
        "came" => "come",
        "knew" | "known" => "know",
        "did" | "done" => "do",
        "had" => "have",
        "made" => "make",
        "took" | "taken" => "take",
        "got" => "get",
        "said" => "say",
        "told" => "tell",
        "gave" | "given" => "give",
        "wrote" | "written" => "write",
        "bought" => "buy",
        "thought" => "think",
        "found" => "find",
        "left" => "leave",
        "felt" => "feel",
        "ate" => "eat",
        "drank" => "drink",
        "began" => "begin",
        "ran" => "run",
        "spoke" => "speak",
        "understood" => "understand",
        "sent" => "send",
        "forgot" => "forget",
        "met" => "meet",
        "paid" => "pay",
        "heard" => "hear",
        "brought" => "bring",
        "wanted" => "want",
        "needed" => "need",
        "liked" => "like",
        "worked" => "work",
        "called" => "call",
        "asked" => "ask",
        "received" => "receive",
        "finished" => "finish",
        "started" => "start",
        "tried" => "try",
        _ => return None,
    })
}

fn gerund(verb: &str) -> String {
    match verb {
        "be" => "being".into(),
        "see" => "seeing".into(),
        "get" => "getting".into(),
        "chat" => "chatting".into(),
        "begin" => "beginning".into(),
        "run" => "running".into(),
        "stop" => "stopping".into(),
        "plan" => "planning".into(),
        "set" => "setting".into(),
        "put" => "putting".into(),
        "try" => "trying".into(),
        v if v.ends_with("ie") => format!("{}ying", &v[..v.len() - 2]),
        v if v.ends_with('e') && !v.ends_with("ee") && v.len() > 2 => format!("{}ing", &v[..v.len() - 1]),
        v => format!("{v}ing"),
    }
}

fn be_to_perfect(subject_be: &str) -> String {
    match subject_be {
        "i am" => "I have been".into(),
        "i'm" | "i’m" => "I've been".into(),
        "we are" => "we have been".into(),
        "we're" | "we’re" => "we've been".into(),
        "they are" => "they have been".into(),
        "they're" | "they’re" => "they've been".into(),
        "you are" => "you have been".into(),
        "you're" | "you’re" => "you've been".into(),
        "he is" => "he has been".into(),
        "he's" | "he’s" => "he's been".into(),
        "she is" => "she has been".into(),
        "she's" | "she’s" => "she's been".into(),
        other => format!("{other} been"),
    }
}

fn subject_of(subject_be: &str) -> (&'static str, bool) {
    // (subject, third person singular)
    let s = subject_be.split(|c: char| c == ' ' || c == '\'' || c == '’').next().unwrap_or("");
    match s {
        "i" => ("I", false),
        "we" => ("we", false),
        "they" => ("they", false),
        "you" => ("you", false),
        "he" => ("he", true),
        "she" => ("she", true),
        "everybody" => ("everybody", true),
        "everyone" => ("everyone", true),
        _ => ("I", false),
    }
}

// --- fix functions ---------------------------------------------------------

fn fix_am_agree(c: &Captures) -> Vec<String> {
    let (subj, third) = subject_of(&lower(c, 1));
    let negative = c.get(2).is_some();
    let v = match (negative, third) {
        (false, false) => "agree",
        (false, true) => "agrees",
        (true, false) => "don't agree",
        (true, true) => "doesn't agree",
    };
    vec![format!("{subj} {v}")]
}

fn fix_tell(c: &Captures) -> Vec<String> {
    let v = match lower(c, 1).as_str() {
        "say" => "tell",
        "says" => "tells",
        "said" => "told",
        "saying" => "telling",
        _ => "tell",
    };
    vec![format!("{v} {}", g(c, 2))]
}

fn fix_teach(c: &Captures) -> Vec<String> {
    let v = match lower(c, 1).as_str() {
        "learn" => "teach",
        "learns" => "teaches",
        "learned" | "learnt" => "taught",
        "learning" => "teaching",
        _ => "teach",
    };
    vec![format!("{v} {}", g(c, 2))]
}

fn fix_lend(c: &Captures) -> Vec<String> {
    let v = match lower(c, 1).as_str() {
        "borrow" => "lend",
        "borrows" => "lends",
        "borrowed" => "lent",
        "borrowing" => "lending",
        _ => "lend",
    };
    vec![format!("{v} {}", g(c, 2))]
}

fn fix_am_since(c: &Captures) -> Vec<String> {
    vec![format!("{} {}{} since", be_to_perfect(&lower(c, 1)), g(c, 2), g(c, 3))]
}

fn fix_am_for(c: &Captures) -> Vec<String> {
    vec![format!("{} {}{} for", be_to_perfect(&lower(c, 1)), g(c, 2), g(c, 3))]
}

fn fix_have_years(c: &Captures) -> Vec<String> {
    let subj = lower(c, 1);
    let be = match subj.as_str() {
        "i have" => "I am",
        "i've" | "i’ve" => "I'm",
        "you have" => "you are",
        "we have" => "we are",
        "they have" => "they are",
        "he has" => "he is",
        "she has" => "she is",
        _ => "I am",
    };
    vec![format!("{be} {} years old", g(c, 2))]
}

fn fix_uncountable(c: &Captures) -> Vec<String> {
    let w = lower(c, 0);
    let singular = w.strip_suffix('s').unwrap_or(&w).to_string();
    vec![singular]
}

fn fix_article_uncountable(c: &Captures) -> Vec<String> {
    let noun = g(c, 2);
    vec![noun.to_string(), format!("a piece of {noun}")]
}

fn fix_people(c: &Captures) -> Vec<String> {
    let v = match lower(c, 1).as_str() {
        "is" => "are",
        "was" => "were",
        "has" => "have",
        "does" => "do",
        "doesn't" | "doesn’t" => "don't",
        "isn't" | "isn’t" => "aren't",
        "wasn't" | "wasn’t" => "weren't",
        other => return vec![format!("people {other}")],
    };
    vec![format!("people {v}")]
}

fn fix_every(c: &Captures) -> Vec<String> {
    let n = lower(c, 1);
    if n == "people" || n == "persons" {
        return vec!["everyone".into(), "every person".into()];
    }
    vec![format!("every {}", n.strip_suffix('s').unwrap_or(&n))]
}

fn fix_more_comparative(c: &Captures) -> Vec<String> {
    let adj = g(c, 2);
    if lower(c, 1) == "much more" {
        vec![format!("much {adj}")]
    } else {
        vec![adj.to_string(), format!("much {adj}")]
    }
}

fn fix_looking_forward(c: &Captures) -> Vec<String> {
    vec![format!("{} forward to {}", g(c, 1), gerund(&lower(c, 2)))]
}

fn fix_day(c: &Captures) -> Vec<String> {
    let day = g(c, 2);
    let mut chars = day.chars();
    let cap = chars.next().map(|f| f.to_uppercase().collect::<String>() + chars.as_str()).unwrap_or_default();
    vec![format!("on {cap}")]
}

fn fix_month(c: &Captures) -> Vec<String> {
    let m = g(c, 2);
    let mut chars = m.chars();
    let cap = chars.next().map(|f| f.to_uppercase().collect::<String>() + chars.as_str()).unwrap_or_default();
    vec![format!("in {cap}")]
}

fn fix_did_past(c: &Captures) -> Vec<String> {
    match base_form(&lower(c, 2)) {
        Some(b) => vec![format!("{} {b}", g(c, 1))],
        None => vec![],
    }
}

fn fix_did_q_past(c: &Captures) -> Vec<String> {
    match base_form(&lower(c, 3)) {
        Some(b) => vec![format!("{} {} {b}", g(c, 1), g(c, 2))],
        None => vec![],
    }
}

fn fix_ed_adjective(c: &Captures) -> Vec<String> {
    let w = lower(c, 1);
    let ed = match w.as_str() {
        "boring" => "bored",
        "interesting" => "interested",
        "exciting" => "excited",
        "tiring" => "tired",
        "confusing" => "confused",
        "disappointing" => "disappointed",
        "frightening" => "frightened",
        "embarrassing" => "embarrassed",
        "annoying" => "annoyed",
        "surprising" => "surprised",
        "satisfying" => "satisfied",
        _ => return vec![],
    };
    vec![ed.into()]
}

fn fix_do_to_make(c: &Captures) -> Vec<String> {
    let v = match lower(c, 1).as_str() {
        "do" => "make",
        "does" => "makes",
        "did" | "done" => "made",
        "doing" => "making",
        _ => "make",
    };
    vec![format!("{v} {}{}", g(c, 2), g(c, 3))]
}

fn fix_make_to_take(c: &Captures) -> Vec<String> {
    let v = match lower(c, 1).as_str() {
        "make" => "take",
        "makes" => "takes",
        "made" => "took",
        "making" => "taking",
        _ => "take",
    };
    vec![format!("{v} {}{}", g(c, 2), g(c, 3))]
}

fn fix_make_to_do(c: &Captures) -> Vec<String> {
    let v = match lower(c, 1).as_str() {
        "make" => "do",
        "makes" => "does",
        "made" => "did",
        "making" => "doing",
        _ => "do",
    };
    vec![format!("{v} {}{}", g(c, 2), g(c, 3))]
}

fn fix_the_abstract(c: &Captures) -> Vec<String> {
    let noun = g(c, 2);
    let mut chars = noun.chars();
    vec![chars.next().map(|f| f.to_uppercase().collect::<String>() + chars.as_str()).unwrap_or_default()]
}

// ---------------------------------------------------------------------------
// The rules
// ---------------------------------------------------------------------------

const PREP_OR_END: &str = r"\s*[.,!?;:)]|\s*$|\s+(?:from|about|on|for|to|of|regarding|please|and|or|but|that|which|when|if|so|because|in|at|with|is|was|are|were)\b";

const NUM: &str = "";

static RULES: &[RuleDef] = &[
    // ----- grammar --------------------------------------------------------
    RuleDef {
        id: "AmAgree", kind: "Grammar", hint: false,
        pattern: r"\b(I am|I'm|I’m|we are|we're|we’re|they are|they're|they’re|you are|you're|you’re|he is|he's|she is|she's|everybody is|everyone is) (not )?agree\b",
        target: 0, fix: Fix::Func(fix_am_agree),
        message: "“Agree” is already a verb, so it doesn’t need “am/is/are”.",
        lesson: LessonDef {
            title: "“Agree” is a verb",
            explanation: "In English, agree is an action verb, just like “like” or “think”. You wouldn’t say “I am like it”, so you don’t say “I am agree”. For the negative, use do/does: “I don’t agree”.",
            wrong: &["I am agree with you.", "She is not agree."],
            right: &["I agree with you.", "She doesn’t agree."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "SinceFor", kind: "Grammar", hint: false,
        pattern: r"\b(since) ((?:\d+|a few|few|several|many|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|a couple of) (?:years?|months?|weeks?|days?|hours?|minutes?|decades?))\b",
        target: 1, fix: Fix::Templates(&["for"]),
        message: "Use “for” with a length of time, and “since” with a starting point.",
        lesson: LessonDef {
            title: "since vs. for",
            explanation: "“For” measures a duration (for 3 years, for two weeks). “Since” marks the moment something started (since 2019, since Monday, since I was a child).",
            wrong: &["I have lived here since 3 years."],
            right: &["I have lived here for 3 years.", "I have lived here since 2021."],
        },
        not_followed: Some(r"\s+ago\b"), must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "SinceLongTime", kind: "Grammar", hint: false,
        pattern: r"\bsince (?:a )?long time\b",
        target: 0, fix: Fix::Templates(&["for a long time"]),
        message: "A length of time takes “for”: “for a long time”.",
        lesson: LessonDef {
            title: "for a long time",
            explanation: "“A long time” is a duration, so it goes with “for”. Also note the article: for **a** long time.",
            wrong: &["I haven’t seen him since long time."],
            right: &["I haven’t seen him for a long time."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "PresentPerfectSince", kind: "Grammar", hint: false,
        pattern: r"\b(I am|I'm|I’m|we are|we're|we’re|they are|they're|they’re|you are|you're|you’re|he is|he's|he’s|she is|she's|she’s) (here|there|living|working|studying|waiting|learning|teaching|using|married|together)((?: [\w'’]+){0,3}) since\b",
        target: 0, fix: Fix::Func(fix_am_since),
        message: "Something that started in the past and continues now needs the present perfect: “have been … since”.",
        lesson: LessonDef {
            title: "Present perfect with “since”",
            explanation: "When an action started in the past and is still true now, English uses the present perfect (have been / have been doing), not the present simple or continuous.",
            wrong: &["I am working here since 2020.", "We are married since May."],
            right: &["I have been working here since 2020.", "We have been married since May."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "PresentPerfectFor", kind: "Grammar", hint: false,
        pattern: r"\b(I am|I'm|I’m|we are|we're|we’re|they are|they're|they’re|you are|you're|you’re|he is|he's|he’s|she is|she's|she’s) (living|working|studying|learning|teaching|using|waiting)((?: [\w'’]+){0,2}) for\b",
        target: 0, fix: Fix::Func(fix_am_for),
        message: "For an activity that has lasted until now, use “have been …ing for”.",
        lesson: LessonDef {
            title: "Present perfect continuous",
            explanation: "To say how long something has been going on until now, use have/has been + -ing + for + duration.",
            wrong: &["I am learning English for five years."],
            right: &["I have been learning English for five years."],
        },
        must_follow: Some(r"\s+(?:\d+|a few|few|several|many|two|three|four|five|six|seven|eight|nine|ten|a long|a couple|ages|years|months|weeks|an hour|a year|a month|a week)\b"),
        not_followed: None, not_preceded: None,
    },
    RuleDef {
        id: "HaveYears", kind: "Grammar", hint: false,
        pattern: r"\b(I have|I've|I’ve|you have|we have|they have|he has|she has) (\d{1,3}) years(?: old)?",
        target: 0, fix: Fix::Func(fix_have_years),
        message: "Age uses “to be” in English: “I am 25 (years old)”.",
        lesson: LessonDef {
            title: "Talking about age",
            explanation: "In English you *are* an age; you don’t *have* it. Say “I am 30” or “I am 30 years old”.",
            wrong: &["I have 30 years."],
            right: &["I am 30.", "I am 30 years old."],
        },
        must_follow: Some(r"\s*[.,!?;:)]|\s*$|\s+and\b"), not_followed: None, not_preceded: None,
    },
    RuleDef {
        id: "Uncountable", kind: "Grammar", hint: false,
        pattern: r"\b(?:informations|advices|furnitures|equipments|knowledges|homeworks|feedbacks|softwares|hardwares|luggages|baggages|garbages|rubbishes)\b",
        target: 0, fix: Fix::Func(fix_uncountable),
        message: "“{fix}” is uncountable in English — it has no plural form.",
        lesson: LessonDef {
            title: "Uncountable nouns",
            explanation: "Some English nouns can’t be counted, so they have no plural and no “a/an”: information, advice, furniture, equipment, knowledge, homework, feedback, software, luggage. To count them, use “a piece of”: two pieces of advice.",
            wrong: &["Thanks for the informations.", "She gave me good advices."],
            right: &["Thanks for the information.", "She gave me good advice / some good pieces of advice."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "ArticleUncountable", kind: "Grammar", hint: false,
        pattern: r"\b(an?) (information|advice|furniture|equipment|homework|luggage|baggage|feedback)\b",
        target: 0, fix: Fix::Func(fix_article_uncountable),
        message: "“{orig}” — uncountable nouns don’t take “a/an”.",
        lesson: LessonDef {
            title: "No “a/an” with uncountable nouns",
            explanation: "Uncountable nouns (information, advice, feedback, homework…) can’t take “a/an”. Drop the article, use “some”, or say “a piece of”.",
            wrong: &["Can I give you an advice?", "I need an information."],
            right: &["Can I give you some advice?", "I need some information / a piece of information."],
        },
        must_follow: Some(PREP_OR_END), not_followed: None, not_preceded: None,
    },
    RuleDef {
        id: "PeopleAre", kind: "Agreement", hint: false,
        pattern: r"\bpeople (is|was|has|does|doesn't|doesn’t|isn't|isn’t|wasn't|wasn’t)\b",
        target: 0, fix: Fix::Func(fix_people),
        message: "“People” is plural, so the verb must be plural too.",
        lesson: LessonDef {
            title: "“People” is plural",
            explanation: "“People” means more than one person, so it takes plural verbs: people are, people were, people have.",
            wrong: &["People is friendly here."],
            right: &["People are friendly here."],
        },
        not_followed: None, must_follow: None, not_preceded: Some(r"\b(?:a|the|one|every)\s+$"),
    },
    RuleDef {
        id: "EverySingular", kind: "Grammar", hint: false,
        pattern: r"\bevery (days|weeks|months|years|times|mornings|evenings|nights|weekends|people|persons)\b",
        target: 0, fix: Fix::Func(fix_every),
        message: "“Every” is always followed by a singular noun.",
        lesson: LessonDef {
            title: "every + singular",
            explanation: "“Every” looks at the items one by one, so the noun after it is singular: every day, every week, every person. (If you want plural, use “all”: all days.)",
            wrong: &["I run every days."],
            right: &["I run every day."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "DoubleComparative", kind: "Grammar", hint: false,
        pattern: r"\b(much more|more) (better|worse|easier|bigger|smaller|faster|cheaper|harder|longer|shorter|higher|lower|larger|older|younger|nicer|simpler|happier|greater|stronger|weaker|richer|newer)\b",
        target: 0, fix: Fix::Func(fix_more_comparative),
        message: "“{orig}” compares twice — “-er” already means “more”.",
        lesson: LessonDef {
            title: "Don’t double the comparison",
            explanation: "Short adjectives get “-er” (bigger, easier) and long ones get “more” (more interesting). Never both. To add emphasis, use “much”: much better.",
            wrong: &["This is more better.", "It’s more easier now."],
            right: &["This is better / much better.", "It’s easier now."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "LookingForwardTo", kind: "Grammar", hint: false,
        pattern: r"\b(look|looks|looking|looked) forward to (see|meet|hear|work|talk|speak|discuss|receive|get|visit|chat|catch|collaborate|join|welcome|read|start|have|be|go|come|share|learn|cooperate|continue|help|show|try|use|seeing you)\b",
        target: 0, fix: Fix::Func(fix_looking_forward),
        message: "After “look forward to”, use the -ing form of the verb.",
        lesson: LessonDef {
            title: "look forward to + -ing",
            explanation: "In “look forward to”, the word “to” is a preposition, not part of an infinitive. Prepositions are followed by nouns or -ing forms.",
            wrong: &["I look forward to hear from you."],
            right: &["I look forward to hearing from you."],
        },
        not_followed: Some(r"ing\b"), must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "DidPast", kind: "Grammar", hint: false,
        pattern: r"\b(didn't|didn’t|did not|doesn't|doesn’t|does not|don't|don’t|do not) (went|gone|saw|seen|came|knew|known|did|done|had|made|took|taken|got|said|told|gave|given|wrote|written|bought|thought|found|left|felt|ate|drank|began|ran|spoke|understood|sent|forgot|met|paid|heard|brought|wanted|needed|liked|worked|called|asked|received|finished|started|tried)\b",
        target: 0, fix: Fix::Func(fix_did_past),
        message: "After “did/does/do”, use the base form of the verb.",
        lesson: LessonDef {
            title: "One past tense is enough",
            explanation: "“Did” already carries the past tense, so the main verb goes back to its base form: didn’t go, didn’t see, did you know.",
            wrong: &["I didn’t went there.", "He doesn’t knew."],
            right: &["I didn’t go there.", "He doesn’t know / didn’t know."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "DidQuestionPast", kind: "Grammar", hint: false,
        pattern: r"\b(did|does|do) (you|he|she|it|we|they|I) (went|saw|came|knew|did|had|made|took|got|said|told|gave|wrote|bought|thought|found|left|felt|ate|drank|began|ran|spoke|understood|sent|forgot|met|paid|heard|brought|wanted|needed|liked|worked|called|asked|received|finished|started|tried)\b",
        target: 0, fix: Fix::Func(fix_did_q_past),
        message: "In questions with “did”, the main verb stays in its base form.",
        lesson: LessonDef {
            title: "Questions with “did”",
            explanation: "“Did” shows the past, so the verb after the subject is the base form: Did you see…? Did she go…?",
            wrong: &["Did you saw the email?"],
            right: &["Did you see the email?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "InterestedIn", kind: "Grammar", hint: false,
        pattern: r"\b(?:am|are|is|was|were|'m|’m|'re|’re|be|been|being|not|very|really|so|quite) (interesting) in\b",
        target: 1, fix: Fix::Templates(&["interested"]),
        message: "To describe how you feel, use “interested”; “interesting” describes the thing.",
        lesson: LessonDef {
            title: "-ed vs. -ing adjectives",
            explanation: "-ed adjectives describe how a person feels (interested, bored, excited). -ing adjectives describe what causes the feeling (interesting, boring, exciting).",
            wrong: &["I am interesting in design."],
            right: &["I am interested in design.", "Design is interesting."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "FeelingEd", kind: "Grammar", hint: true,
        pattern: r"\b(?:I am|I'm|I’m|I was|we are|we're|we’re|we were|I feel|I felt|I got|I get) (?:so |very |really |a bit |a little |quite |too |kind of |totally |completely )?(boring|exciting|tiring|confusing|disappointing|frightening|embarrassing|annoying|surprising|satisfying)\b",
        target: 1, fix: Fix::Func(fix_ed_adjective),
        message: "Did you mean how you *feel*? That’s “{fix}”. “{orig}” describes something that causes the feeling.",
        lesson: LessonDef {
            title: "-ed vs. -ing adjectives",
            explanation: "“I am bored” = I feel no interest. “I am boring” = I make other people bored! -ed is the feeling, -ing is the cause.",
            wrong: &["I am so boring today. (meaning: nudím se)"],
            right: &["I am so bored today.", "This meeting is boring."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "ItDepends", kind: "Grammar", hint: false,
        pattern: r"\b(?:it's|it’s|it is|it) depend\b",
        target: 0, fix: Fix::Templates(&["it depends"]),
        message: "The phrase is “it depends”.",
        lesson: LessonDef {
            title: "It depends",
            explanation: "“Depend” is a normal verb: it depends (third person -s). No “is” needed.",
            wrong: &["It’s depend on the weather."],
            right: &["It depends on the weather."],
        },
        not_followed: None, must_follow: None, not_preceded: Some(r"\b(?:does|did|will|would|could|might|may|should|can|to|doesn't|doesn’t|didn't|didn’t|won't|won’t)\s+$"),
    },
    RuleDef {
        id: "TheAbstract", kind: "Grammar", hint: true,
        pattern: r"(?:^|[.!?]\s+)((?:the) (life|nature|society|happiness|love)) (?:is|was|can|has)\b",
        target: 1, fix: Fix::Func(fix_the_abstract),
        message: "When you talk about “{fix}” in general, English uses no article.",
        lesson: LessonDef {
            title: "No “the” for things in general",
            explanation: "Abstract nouns used in a general sense take no article: Life is short. Nature is beautiful. Use “the” only for a specific one: the life of Mozart.",
            wrong: &["The life is beautiful."],
            right: &["Life is beautiful.", "The life of a student is busy."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "AreHe", kind: "Agreement", hint: false,
        pattern: r"\b(are|were|aren't|aren’t|weren't|weren’t) (he|she|it)\b",
        target: 1, fix: Fix::Func(|c| {
            let v = match g(c, 1).to_lowercase().replace('’', "'").as_str() {
                "are" => "is", "were" => "was", "aren't" => "isn't", _ => "wasn't",
            };
            vec![v.to_string()]
        }),
        message: "“{orig}” doesn’t match the subject — he/she/it takes “{fix}”.",
        lesson: LessonDef {
            title: "is / are with he, she, it",
            explanation: "The verb has to agree with its subject, even in questions where the verb comes first. He, she and it take is/was; you, we and they take are/were.",
            wrong: &["Why are he so cool?", "Were she at the meeting?"],
            right: &["Why is he so cool?", "Was she at the meeting?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "IsThey", kind: "Agreement", hint: false,
        pattern: r"\b(is|was|isn't|isn’t|wasn't|wasn’t) (they|we|you)\b",
        target: 1, fix: Fix::Func(|c| {
            let v = match g(c, 1).to_lowercase().replace('’', "'").as_str() {
                "is" => "are", "was" => "were", "isn't" => "aren't", _ => "weren't",
            };
            vec![v.to_string()]
        }),
        message: "With “{orig}”, the subject needs “{fix}”.",
        lesson: LessonDef {
            title: "is / are with they, we, you",
            explanation: "You, we and they always take are/were — also in questions, where the verb comes before the subject.",
            wrong: &["Is they ready?", "Was you there?"],
            right: &["Are they ready?", "Were you there?"],
        },
        not_followed: None, must_follow: None, not_preceded: Some(r"\b(?:it|this|that|who|what)\s+$"),
    },
    RuleDef {
        id: "HeDoesnt", kind: "Agreement", hint: false,
        pattern: r"\b(he|she|it) (don't|don’t|do not|have|are)\b",
        target: 2, fix: Fix::Func(|c| {
            let v = match g(c, 2).to_lowercase().replace('’', "'").as_str() {
                "don't" => "doesn't", "do not" => "does not", "have" => "has", _ => "is",
            };
            vec![v.to_string()]
        }),
        message: "He, she and it take “{fix}”, not “{orig}”.",
        lesson: LessonDef {
            title: "he/she/it + -s",
            explanation: "In the present simple, he/she/it needs the -s form: he has, she doesn’t, it is. Only I/you/we/they use have, don’t and are.",
            wrong: &["He don’t know.", "She have a car."],
            right: &["He doesn’t know.", "She has a car."],
        },
        not_followed: None, must_follow: None,
        not_preceded: Some(r"\b(?:should|would|could|might|must|will|shall|can|did|does|do|if|wish|though|let|make|makes|made|that|which|who|whom|whether|and|or|nor)\s+$"),
    },
    RuleDef {
        id: "DoesThey", kind: "Agreement", hint: false,
        pattern: r"\b(does|doesn't|doesn’t) (I|you|we|they)\b",
        target: 1, fix: Fix::Func(|c| {
            let v = if g(c, 1).to_lowercase() == "does" { "do" } else { "don't" };
            vec![v.to_string()]
        }),
        message: "I, you, we and they take “{fix}”.",
        lesson: LessonDef {
            title: "do / does",
            explanation: "Does is only for he, she and it. With I, you, we and they, use do.",
            wrong: &["Does they know?"],
            right: &["Do they know?", "Does she know?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "DoHe", kind: "Agreement", hint: false,
        pattern: r"\b(do|don't|don’t) (he|she)\b",
        target: 1, fix: Fix::Func(|c| {
            let v = if g(c, 1).to_lowercase() == "do" { "does" } else { "doesn't" };
            vec![v.to_string()]
        }),
        message: "He and she take “{fix}”.",
        lesson: LessonDef {
            title: "do / does",
            explanation: "Questions and negatives with he, she or it use does / doesn’t.",
            wrong: &["Do he like it?"],
            right: &["Does he like it?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "TheyWere", kind: "Agreement", hint: false,
        pattern: r"\b(they|we|you) (was|wasn't|wasn’t)\b",
        target: 0, fix: Fix::Func(|c| {
            let v = match g(c, 2).to_lowercase().as_str() { "was" => "were", _ => "weren't" };
            vec![format!("{} {v}", g(c, 1))]
        }),
        message: "With “{fix}”, the past of “be” is “were”.",
        lesson: LessonDef {
            title: "was vs. were",
            explanation: "I/he/she/it → was. You/we/they → were. “You” always takes “were”, even when it means one person.",
            wrong: &["They was closed.", "You was right."],
            right: &["They were closed.", "You were right."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "ItsItIs", kind: "Grammar", hint: false,
        pattern: r"\b(its) (?:not|a|an|the|very|so|really|been|going|time|ok|okay|fine|true|important|possible|impossible|hard|easy|good|great|nice|clear|just|also|still|always|never|too|quite|getting|done|over|here|there|about|like|because|probably|definitely|actually|me|you|him|her|us|them|my|your|our|their|this|that|what|how|why|when|worth|raining|late|early|better|best|bad|worse|cold|hot|funny|interesting)\b",
        target: 1, fix: Fix::Templates(&["it's"]),
        message: "“It’s” (with an apostrophe) = “it is / it has”. “Its” = belonging to it.",
        lesson: LessonDef {
            title: "its vs. it’s",
            explanation: "It’s = it is or it has (It’s raining. It’s been fun). Its = possessive, like his/her (The dog wagged its tail). Test: if you can say “it is”, write it’s.",
            wrong: &["Its not correct.", "Its a good idea."],
            right: &["It’s not correct.", "The app has its own dictionary."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    // ----- word usage / prepositions -------------------------------------
    RuleDef {
        id: "DiscussAbout", kind: "Usage", hint: false,
        pattern: r"\b(discuss|discussed|discussing|discusses) about\b",
        target: 0, fix: Fix::Templates(&["${1}"]),
        message: "“Discuss” already means “talk about”, so it doesn’t take “about”.",
        lesson: LessonDef {
            title: "discuss (no “about”)",
            explanation: "The verb “discuss” takes a direct object: discuss the plan. The noun is different: a discussion about the plan.",
            wrong: &["Let’s discuss about the budget."],
            right: &["Let’s discuss the budget.", "Let’s talk about the budget."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "EmphasizeOn", kind: "Usage", hint: false,
        pattern: r"\b(emphasi[sz]e|emphasi[sz]es|emphasi[sz]ed|emphasi[sz]ing) on\b",
        target: 0, fix: Fix::Templates(&["${1}"]),
        message: "“Emphasize” takes a direct object — no “on”.",
        lesson: LessonDef {
            title: "emphasize (no “on”)",
            explanation: "The verb takes a direct object (emphasize the risk). The noun takes “on” (put emphasis on the risk).",
            wrong: &["We emphasize on quality."],
            right: &["We emphasize quality.", "We put emphasis on quality."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "DependOn", kind: "Usage", hint: false,
        pattern: r"\b(depend|depends|depended|depending|dependent) (?:of|from)\b",
        target: 0, fix: Fix::Templates(&["${1} on"]),
        message: "In English you depend *on* something.",
        lesson: LessonDef {
            title: "depend on",
            explanation: "“Depend” always goes with “on” (or “upon” in formal writing).",
            wrong: &["It depends of the price."],
            right: &["It depends on the price."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "ExplainTo", kind: "Usage", hint: false,
        pattern: r"\b(explain|explained|explaining|explains) (me|us)\b",
        target: 0, fix: Fix::Templates(&["${1} to ${2}"]),
        message: "You explain something *to* someone.",
        lesson: LessonDef {
            title: "explain something to someone",
            explanation: "“Explain” can’t take the person directly. Use “explain it to me” or “explain to me how…”.",
            wrong: &["Can you explain me the process?"],
            right: &["Can you explain the process to me?", "Can you explain to me how it works?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "SayTell", kind: "Usage", hint: false,
        pattern: r"\b(say|says|said|saying) (me|us|him)\b",
        target: 0, fix: Fix::Func(fix_tell),
        message: "Use “tell” when you mention the person you’re speaking to.",
        lesson: LessonDef {
            title: "say vs. tell",
            explanation: "“Tell” takes the listener directly (tell me, told him). “Say” doesn’t — use “say something (to someone)”.",
            wrong: &["She said me the news."],
            right: &["She told me the news.", "She said it to me."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "LearnTeach", kind: "Usage", hint: false,
        pattern: r"\b(learn|learns|learned|learnt|learning) (me|us|him)\b",
        target: 0, fix: Fix::Func(fix_teach),
        message: "When someone gives the knowledge, it’s “teach”.",
        lesson: LessonDef {
            title: "learn vs. teach",
            explanation: "You learn (you receive knowledge). Someone teaches you (they give knowledge).",
            wrong: &["My dad learned me to swim."],
            right: &["My dad taught me to swim.", "I learned to swim from my dad."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "BorrowLend", kind: "Usage", hint: false,
        pattern: r"\b(borrow|borrows|borrowed|borrowing) (me|us|him)\b",
        target: 0, fix: Fix::Func(fix_lend),
        message: "When you give something temporarily, it’s “lend”.",
        lesson: LessonDef {
            title: "borrow vs. lend",
            explanation: "You borrow something *from* someone (you take it). You lend something *to* someone (you give it).",
            wrong: &["Can you borrow me your charger?"],
            right: &["Can you lend me your charger?", "Can I borrow your charger?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "ListenTo", kind: "Usage", hint: false,
        pattern: r"\b(listen|listens|listened|listening) (music|the|my|your|his|our|their|this|that|these|those|it|me|him|us|them|podcasts?|radio|songs?|a song)\b",
        target: 0, fix: Fix::Templates(&["${1} to ${2}"]),
        message: "You listen *to* something.",
        lesson: LessonDef {
            title: "listen to",
            explanation: "“Listen” needs “to” before what you hear. (“Hear” doesn’t: I hear music.)",
            wrong: &["I listen music every day."],
            right: &["I listen to music every day."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "WaitFor", kind: "Usage", hint: false,
        pattern: r"\b(wait|waits|waited|waiting) (you|me|him|us|them)\b",
        target: 0, fix: Fix::Templates(&["${1} for ${2}"]),
        message: "You wait *for* someone.",
        lesson: LessonDef {
            title: "wait for",
            explanation: "“Wait” is followed by “for” before the person or thing: wait for me, wait for the bus.",
            wrong: &["I will wait you outside."],
            right: &["I will wait for you outside."],
        },
        not_followed: Some(r"\s+out\b"), must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "ContactWith", kind: "Usage", hint: false,
        pattern: r"\b(contact|contacted|contacting|contacts) with (me|us|him|her|them|you)\b",
        target: 0, fix: Fix::Templates(&["${1} ${2}"]),
        message: "The verb “contact” takes the person directly.",
        lesson: LessonDef {
            title: "contact someone",
            explanation: "As a verb, “contact” needs no preposition: contact me. As a noun, use “in contact with”.",
            wrong: &["Please contact with me tomorrow."],
            right: &["Please contact me tomorrow.", "We are in contact with them."],
        },
        not_followed: None, must_follow: None, not_preceded: Some(r"\b(?:in|into|close|direct|eye|regular|personal|no|any|stay|keep|kept|lost|our|first)\s+$"),
    },
    RuleDef {
        id: "MarryWith", kind: "Usage", hint: false,
        pattern: r"\b(marry|marries) with\b",
        target: 0, fix: Fix::Templates(&["${1}"]),
        message: "You marry someone — no “with”.",
        lesson: LessonDef {
            title: "marry someone / be married to someone",
            explanation: "The verb takes the person directly: She married Tom. The adjective uses “to”: She is married to Tom.",
            wrong: &["He wants to marry with her."],
            right: &["He wants to marry her."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "QuestionFor", kind: "Usage", hint: false,
        pattern: r"\b(?:a|one|another|some|few|couple of|two|three) questions? (to) (?:you|him|her|them|us)\b",
        target: 1, fix: Fix::Templates(&["for"]),
        message: "You have a question *for* someone.",
        lesson: LessonDef {
            title: "a question for you",
            explanation: "Use “for” with the person who should answer: I have a question for you. (You ask a question *of* someone in formal English.)",
            wrong: &["I have a question to you."],
            right: &["I have a question for you."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "AccordingToMe", kind: "Usage", hint: false,
        pattern: r"\baccording to me\b",
        target: 0, fix: Fix::Templates(&["in my opinion", "I think"]),
        message: "Native speakers say “in my opinion” or “I think”.",
        lesson: LessonDef {
            title: "Giving your opinion",
            explanation: "“According to” is used for other sources (according to the report). For yourself, say “in my opinion”, “I think”, or “as I see it”.",
            wrong: &["According to me, it’s too expensive."],
            right: &["In my opinion, it’s too expensive.", "I think it’s too expensive."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "HowDoYouCall", kind: "Usage", hint: false,
        pattern: r"\bhow (do|does|did) (you|we|they|people|one) call\b",
        target: 0, fix: Fix::Templates(&["what ${1} ${2} call"]),
        message: "When asking for a name, English uses “what”, not “how”.",
        lesson: LessonDef {
            title: "What do you call…?",
            explanation: "To ask for the name of something, use “What do you call…?” or “What is … called?”.",
            wrong: &["How do you call this in English?"],
            right: &["What do you call this in English?", "What is this called in English?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "SameAs", kind: "Usage", hint: false,
        pattern: r"\bthe same like\b",
        target: 0, fix: Fix::Templates(&["the same as"]),
        message: "The fixed phrase is “the same as”.",
        lesson: LessonDef {
            title: "the same as",
            explanation: "“Same” pairs with “as”: the same as yours. “Like” pairs with “similar”: similar to / like yours.",
            wrong: &["My phone is the same like yours."],
            right: &["My phone is the same as yours."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "OnTheOtherHand", kind: "Usage", hint: false,
        pattern: r"(?:^|[.!?]\s+)(on the other side),",
        target: 1, fix: Fix::Templates(&["On the other hand"]),
        message: "To introduce a contrast, English says “on the other hand”.",
        lesson: LessonDef {
            title: "on the other hand",
            explanation: "“On the other side” is about physical place (the other side of the road). For a contrasting argument, use “on the other hand”.",
            wrong: &["It’s cheap. On the other side, it’s slow."],
            right: &["It’s cheap. On the other hand, it’s slow."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "MostOf", kind: "Usage", hint: false,
        pattern: r"\bthe most of (?:the|my|your|his|her|our|their|them|us|people|these|those|it)\b",
        target: 0, fix: Fix::Func(|c| vec![g(c, 0)[4..].to_string()]),
        message: "To mean “the majority”, say “most of” without “the”.",
        lesson: LessonDef {
            title: "most of (no “the”)",
            explanation: "“Most of the people” = the majority. “The most” is a superlative (the most beautiful). Exception: the idiom “make the most of something”.",
            wrong: &["The most of my friends live abroad."],
            right: &["Most of my friends live abroad."],
        },
        not_followed: None, must_follow: None, not_preceded: Some(r"\b(?:make|makes|made|making|get|got|getting)\s+$"),
    },
    RuleDef {
        id: "AtTheEnd", kind: "Usage", hint: false,
        pattern: r"\bin the end of\b",
        target: 0, fix: Fix::Templates(&["at the end of"]),
        message: "The end *of* something is “at the end of”.",
        lesson: LessonDef {
            title: "at the end of vs. in the end",
            explanation: "“At the end of” = at the final point of something (at the end of the month). “In the end” (no “of”) = finally, after everything.",
            wrong: &["We’ll pay in the end of May."],
            right: &["We’ll pay at the end of May.", "In the end, we paid."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "AtTheSameTime", kind: "Usage", hint: false,
        pattern: r"\bin the same time\b",
        target: 0, fix: Fix::Templates(&["at the same time"]),
        message: "The fixed phrase is “at the same time”.",
        lesson: LessonDef {
            title: "at the same time",
            explanation: "Points in time take “at”: at the same time, at 5 o’clock, at the moment.",
            wrong: &["They arrived in the same time."],
            right: &["They arrived at the same time."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "InTheMorning", kind: "Usage", hint: false,
        pattern: r"\bat the (morning|afternoon|evening)\b",
        target: 0, fix: Fix::Templates(&["in the ${1}"]),
        message: "Parts of the day take “in”: in the morning.",
        lesson: LessonDef {
            title: "in the morning, at night",
            explanation: "Parts of the day: in the morning, in the afternoon, in the evening — but at night, at noon, at midnight.",
            wrong: &["I work best at the morning."],
            right: &["I work best in the morning."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "AtTheWeekend", kind: "Usage", hint: false,
        pattern: r"\bin the weekend\b",
        target: 0, fix: Fix::Templates(&["on the weekend", "at the weekend"]),
        message: "Use “on the weekend” (US) or “at the weekend” (UK).",
        lesson: LessonDef {
            title: "on / at the weekend",
            explanation: "American English: on the weekend. British English: at the weekend. Both: over the weekend.",
            wrong: &["Let’s meet in the weekend."],
            right: &["Let’s meet on the weekend.", "Let’s meet at the weekend."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "OnDays", kind: "Usage", hint: false,
        pattern: r"\b(in|at) (monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\b",
        target: 0, fix: Fix::Func(fix_day),
        message: "Days take “on”: on Monday.",
        lesson: LessonDef {
            title: "on + days",
            explanation: "Time prepositions: at + clock time (at 5), on + days and dates (on Monday, on 3 May), in + months, years, seasons (in May, in 2025).",
            wrong: &["See you in Monday."],
            right: &["See you on Monday."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "InMonths", kind: "Usage", hint: false,
        pattern: r"\b(at|on) (january|february|april|june|july|august|september|october|november|december)\b",
        target: 0, fix: Fix::Func(fix_month),
        message: "Months take “in”: in June.",
        lesson: LessonDef {
            title: "in + months",
            explanation: "Months, years and seasons take “in”: in June, in 2025, in winter. Only a specific date takes “on”: on June 5.",
            wrong: &["The course starts at September."],
            right: &["The course starts in September.", "The course starts on September 5."],
        },
        not_followed: Some(r"\s*\d"), must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "GoHome", kind: "Usage", hint: false,
        pattern: r"\b(go|goes|went|going|gone|come|comes|came|coming|get|gets|got|getting|arrive|arrived|arriving|return|returned|returning|walk|walked|walking|drive|drove|driving|run|ran|running|head|headed|heading) to home\b",
        target: 0, fix: Fix::Templates(&["${1} home"]),
        message: "With movement verbs, “home” needs no “to”.",
        lesson: LessonDef {
            title: "go home",
            explanation: "“Home” works like an adverb after verbs of movement: go home, come home, get home. (But: at home, to my home.)",
            wrong: &["I’m going to home."],
            right: &["I’m going home."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "OnTheInternet", kind: "Usage", hint: false,
        pattern: r"\bin the internet\b",
        target: 0, fix: Fix::Templates(&["on the internet"]),
        message: "Things are *on* the internet.",
        lesson: LessonDef {
            title: "on the internet",
            explanation: "Media and platforms take “on”: on the internet, on TV, on the radio, on YouTube, on the phone.",
            wrong: &["I found it in the internet."],
            right: &["I found it on the internet."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "OnTV", kind: "Usage", hint: true,
        pattern: r"\bin (?:the )?tv\b",
        target: 0, fix: Fix::Templates(&["on TV"]),
        message: "Programmes are *on* TV.",
        lesson: LessonDef {
            title: "on TV",
            explanation: "What you watch is on TV (on the radio, on YouTube). “In TV” only appears when talking about the industry: she works in TV.",
            wrong: &["I saw it in TV."],
            right: &["I saw it on TV."],
        },
        not_followed: None, must_follow: None, not_preceded: Some(r"\b(?:work|works|worked|working|career|job|jobs|careers)\s+$"),
    },
    RuleDef {
        id: "InThePhoto", kind: "Usage", hint: true,
        pattern: r"\b(on) (?:the|this|that|my|your|a) (?:photo|picture|photograph|image|selfie)\b",
        target: 1, fix: Fix::Templates(&["in"]),
        message: "People and things appear *in* a photo.",
        lesson: LessonDef {
            title: "in the photo",
            explanation: "What you can see in an image is “in the photo / in the picture”. “On” is for actions done to the image: click on the photo, comment on the photo.",
            wrong: &["Who is that on the photo?"],
            right: &["Who is that in the photo?"],
        },
        not_followed: None, must_follow: None,
        not_preceded: Some(r"\b(?:click|clicked|clicking|clicks|tap|tapped|tapping|taps|comment|commented|commenting|comments|work|worked|working|based|focus|focused|vote|voted|edit|edited|press|pressed|zoom|zoomed|put|drew|draw|write|wrote|stand|feedback|likes?|reactions?|edits?|text|caption|stickers?|filters?|effects?|signed|sign|stamp|stamped|watermark|spend|spent|hover|hovered|double-click|double-clicked|right-click|right-clicked|act|acting|depend|depends|rely|relies)\s+$"),
    },
    RuleDef {
        id: "AtUniversity", kind: "Usage", hint: false,
        pattern: r"\b(?:study|studies|studied|studying|student|teach|teaches|taught|teaching|work|works|worked|working|lecturer|professor) (on) (?:the |a )?university\b",
        target: 1, fix: Fix::Templates(&["at"]),
        message: "You study or work *at* a university.",
        lesson: LessonDef {
            title: "at university",
            explanation: "Institutions take “at”: at university, at school, at work. (British: “at university”; American: “in college”.)",
            wrong: &["I study on university."],
            right: &["I study at university.", "I study at Charles University."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "ThankGod", kind: "Usage", hint: false,
        pattern: r"\bthanks god\b",
        target: 0, fix: Fix::Templates(&["thank God"]),
        message: "The expression is “thank God”.",
        lesson: LessonDef {
            title: "thank God",
            explanation: "It’s a short form of “I thank God”, so “thank” is a verb with no -s. “God” is capitalised.",
            wrong: &["Thanks god it’s Friday."],
            right: &["Thank God it’s Friday."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    // ----- collocations --------------------------------------------------
    RuleDef {
        id: "MakeMistake", kind: "WordChoice", hint: false,
        pattern: r"\b(do|does|did|doing|done) ((?:a |an |some |many |few |the same |so many |lots of |a lot of |several |one |two |stupid |silly |big |small |a big |a small |a stupid |a silly |no )?)(mistakes?)\b",
        target: 0, fix: Fix::Func(fix_do_to_make),
        message: "In English you *make* a mistake.",
        lesson: LessonDef {
            title: "make a mistake",
            explanation: "Mistakes are “made”, never “done”: make a mistake, made two mistakes, everyone makes mistakes.",
            wrong: &["I did a mistake in the report."],
            right: &["I made a mistake in the report."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "MakeDecision", kind: "WordChoice", hint: false,
        pattern: r"\b(do|does|did|doing|done) ((?:a |the |this |that |my |your |our |their |his |her |an important |a big |a quick |the right |the wrong |a good |a bad |a final |any |no )?)(decisions?)\b",
        target: 0, fix: Fix::Func(fix_do_to_make),
        message: "In English you *make* a decision.",
        lesson: LessonDef {
            title: "make a decision",
            explanation: "Decisions are made: make a decision, made the right decision. (British English also accepts “take a decision”.)",
            wrong: &["We need to do a decision today."],
            right: &["We need to make a decision today."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "TakePhoto", kind: "WordChoice", hint: false,
        pattern: r"\b(make|makes|made|making) ((?:a |some |many |few |nice |a nice |a few |the |lots of |a lot of |more |great |a great |a quick |good |a good )?)(photos?|photographs?|selfies?|snapshots?)\b",
        target: 0, fix: Fix::Func(fix_make_to_take),
        message: "In English you *take* a photo.",
        lesson: LessonDef {
            title: "take a photo",
            explanation: "With cameras and phones, English uses “take”: take a photo, take a picture, take a selfie.",
            wrong: &["Can you make a photo of us?"],
            right: &["Can you take a photo of us?"],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "DoHomework", kind: "WordChoice", hint: false,
        pattern: r"\b(make|makes|made|making) ((?:my |your |his |her |our |their |the |some )?)(homework|housework|sports?)\b",
        target: 0, fix: Fix::Func(fix_make_to_do),
        message: "With homework, housework and sport, English uses “do”.",
        lesson: LessonDef {
            title: "do homework, do sport",
            explanation: "“Do” is used for tasks, work and activities: do homework, do the housework, do sport, do exercise, do the dishes.",
            wrong: &["I make sport three times a week."],
            right: &["I do sport three times a week."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
    RuleDef {
        id: "TakeExam", kind: "WordChoice", hint: true,
        pattern: r"\b(make|makes|made|making|do|does|did|doing) (an |the |my |this |that |the final |a final |an oral |a written )(exams?)\b",
        target: 0, fix: Fix::Func(|c| {
            let v = match g(c, 1).to_lowercase().as_str() {
                "make" | "do" => "take",
                "makes" | "does" => "takes",
                "made" | "did" => "took",
                _ => "taking",
            };
            vec![format!("{v} {}{}", g(c, 2), g(c, 3))]
        }),
        message: "Students *take* (or *sit*) an exam.",
        lesson: LessonDef {
            title: "take an exam",
            explanation: "As a student you take (UK: sit) an exam, and then you pass or fail it. A teacher “sets” or “writes” an exam.",
            wrong: &["I have to make an exam tomorrow."],
            right: &["I have to take an exam tomorrow."],
        },
        not_followed: None, must_follow: None, not_preceded: None,
    },
];

#[allow(dead_code)]
const _UNUSED: &str = NUM;

#[cfg(test)]
mod tests {
    use super::*;

    fn fixes(text: &str) -> Vec<(String, String, Vec<String>)> {
        let coach = Coach::new();
        coach
            .check(text)
            .into_iter()
            .map(|l| (l.rule, text[l.byte_start..l.byte_end].to_string(), l.suggestions))
            .collect()
    }

    #[test]
    fn rules_compile() {
        let _ = Coach::new();
    }

    #[test]
    fn examples() {
        let cases: &[(&str, &str, &str)] = &[
            ("I am agree with you.", "I am agree", "I agree"),
            ("She is not agree.", "She is not agree", "She doesn't agree"),
            ("I live here since 3 years.", "since", "for"),
            ("I am working here since 2020.", "I am working here since", "I have been working here since"),
            ("I'm learning English for five years.", "I'm learning English for", "I've been learning English for"),
            ("I have 30 years.", "I have 30 years", "I am 30 years old"),
            ("Thanks for the informations.", "informations", "information"),
            ("Can I give you an advice?", "an advice", "advice"),
            ("I didn't went there.", "didn't went", "didn't go"),
            ("Did you saw it?", "Did you saw", "Did you see"),
            ("Let's discuss about it.", "discuss about", "discuss"),
            ("I look forward to hear from you.", "look forward to hear", "look forward to hearing"),
            ("Can you explain me this?", "explain me", "explain to me"),
            ("I did a mistake.", "did a mistake", "made a mistake"),
            ("Can you make a photo?", "make a photo", "take a photo"),
            ("I'm going to home.", "going to home", "going home"),
            ("See you in monday.", "in monday", "on Monday"),
            ("It's depend on you.", "It's depend", "It depends"),
            ("This is more better.", "more better", "better"),
            ("I listen music.", "listen music", "listen to music"),
            ("I'm so boring today.", "boring", "bored"),
            ("They was closed.", "They was", "They were"),
            ("Its not correct.", "Its", "It's"),
            ("Why are he so cool?", "are", "is"),
            ("Is they ready?", "Is", "Are"),
            ("He don't know.", "don't", "doesn't"),
            ("Does they know?", "Does", "Do"),
            ("Do he like it?", "Do", "Does"),
        ];
        for (text, flagged, fix) in cases {
            let f = fixes(text);
            let hit = f.iter().find(|(_, o, _)| o.replace("'", "") == flagged.replace("'", "") || o == flagged);
            assert!(hit.is_some(), "no lint for {text:?}: {f:?}");
            let (_, _, s) = hit.unwrap();
            assert_eq!(s.first().map(|s| s.as_str()), Some(*fix), "for {text:?}");
        }
    }

    #[test]
    fn no_false_positives() {
        let clean = [
            "I agree with you.",
            "I have lived here for 3 years.",
            "I moved here 3 years ago, since 3 years ago things changed.",
            "Let's make the most of it.",
            "We are in contact with them.",
            "Please click on the photo to enlarge it.",
            "I didn't go there.",
            "This is a feedback loop.",
            "I have 5 years of experience.",
            "Discussion about the plan.",
            "The actual problem is the price.",
            "Does it depend on the weather?",
            "She was sympathetic to my problem.",
            "Should he have called?",
            "It is you who decides.",
            "I'll do it tomorrow.",
            "If it were up to me.",
            "Does she have time?",
            "I'm interested in design.",
        ];
        for t in clean {
            let f = fixes(t);
            assert!(f.is_empty(), "false positive on {t:?}: {f:?}");
        }
    }
}
