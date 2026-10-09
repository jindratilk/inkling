//! Inkling engine — a thin, fast C ABI around Harper plus a custom
//! "coach" linter for common English learner mistakes.
//!
//! Everything runs in-process. No I/O, no networking, no persistence.

mod coach;

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, CStr, CString};
use std::sync::Arc;

use harper_core::linting::{Lint, LintGroup, Suggestion};
use harper_core::spell::{Dictionary, FstDictionary, MergedDictionary, MutableDictionary};
use harper_core::{Dialect, DictWordMetadata, Document};
use serde::{Deserialize, Serialize};

pub use coach::CoachLint;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct EngineConfig {
    /// "american" | "british" | "canadian" | "australian" | "indian"
    pub dialect: String,
    /// Words the user taught Inkling.
    pub user_words: Vec<String>,
    /// Harper / coach rule names to switch off.
    pub disabled_rules: Vec<String>,
    /// Learner coach rules on/off.
    pub coach: bool,
    /// Style & readability suggestions on/off.
    pub style: bool,
}

fn parse_dialect(s: &str) -> Dialect {
    match s.to_ascii_lowercase().as_str() {
        "british" | "uk" => Dialect::British,
        "canadian" | "ca" => Dialect::Canadian,
        "australian" | "au" => Dialect::Australian,
        "indian" | "in" => Dialect::Indian,
        _ => Dialect::American,
    }
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct OutLint {
    /// Stable rule identifier (Harper rule name, or `Coach.<id>`).
    pub rule: String,
    /// Harper LintKind key (Spelling, Grammar, ...).
    pub kind: String,
    /// UTF-16 offsets into the checked text (what AppKit / AX speak).
    pub start: usize,
    pub end: usize,
    /// The exact flagged text.
    pub original: String,
    pub message: String,
    pub priority: u8,
    /// Full replacement strings for `original` (already resolved from
    /// insert-after / remove suggestions).
    pub suggestions: Vec<String>,
    /// General description of the rule (Markdown-ish).
    pub description: String,
    /// Rich teaching content for coach rules.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lesson: Option<coach::Lesson>,
    /// "error" | "hint"
    pub severity: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CheckResult {
    lints: Vec<OutLint>,
    micros: u128,
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

pub struct Engine {
    dictionary: Arc<MergedDictionary>,
    group: LintGroup,
    descriptions: HashMap<String, String>,
    disabled: HashSet<String>,
    config: EngineConfig,
    coach: coach::Coach,
}

const CHAT_WORDS: &[&str] = &[
    "wtf", "lol", "lmao", "omg", "btw", "fyi", "asap", "imo", "imho", "tbh", "idk", "afaik", "irl",
    "brb", "rofl", "smh", "ngl", "iirc", "tl;dr", "tldr", "eta", "aka", "diy", "faq", "ok", "okay",
];

const STYLE_KINDS: &[&str] = &["Style", "Readability", "Enhancement", "Redundancy"];

impl Engine {
    pub fn new(config: EngineConfig) -> Self {
        let mut merged = MergedDictionary::new();

        let mut user = MutableDictionary::new();
        // Everyday chat abbreviations are deliberate, not misspellings.
        for w in CHAT_WORDS {
            user.append_word_str(w, DictWordMetadata::default());
        }
        for w in config.user_words.iter().filter(|w| !w.trim().is_empty()) {
            user.append_word_str(w.trim(), DictWordMetadata::default());
            // Also accept the lowercase / capitalised variants people actually type.
            let lower = w.trim().to_lowercase();
            if lower != w.trim() {
                user.append_word_str(&lower, DictWordMetadata::default());
            }
        }
        // Personal words first: the first dictionary that knows a word decides how
        // it may be written (Harper's curated list only allows e.g. "WTF" in caps).
        merged.add_dictionary(Arc::new(user));
        merged.add_dictionary(FstDictionary::curated());
        let dictionary = Arc::new(merged);

        let mut group = LintGroup::new_curated(dictionary.clone(), parse_dialect(&config.dialect));

        for rule in &config.disabled_rules {
            if group.contains_key(rule) {
                group.config.set_rule_enabled(rule, false);
            }
        }

        let descriptions = group
            .all_descriptions()
            .into_iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();

        Self {
            dictionary,
            group,
            descriptions,
            disabled: config.disabled_rules.iter().cloned().collect(),
            coach: coach::Coach::new(),
            config,
        }
    }

    /// Lint `text`, returning lints with UTF-16 spans.
    pub fn check(&mut self, text: &str) -> Vec<OutLint> {
        if text.trim().is_empty() {
            return Vec::new();
        }

        let document = Document::new_plain_english(text, self.dictionary.as_ref());
        let chars: Vec<char> = text.chars().collect();

        // char index -> utf16 offset prefix table
        let mut utf16_at = Vec::with_capacity(chars.len() + 1);
        let mut acc = 0usize;
        for c in &chars {
            utf16_at.push(acc);
            acc += c.len_utf16();
        }
        utf16_at.push(acc);

        let organized = self.group.organized_lints(&document);

        // Collect (rule, lint) pairs so we can resolve overlaps globally.
        let mut tagged: Vec<(String, Lint)> = Vec::new();
        for (rule, lints) in organized {
            if self.disabled.contains(&rule) {
                continue;
            }
            for lint in lints {
                let kind = lint.lint_kind.to_string_key();
                if !self.config.style && STYLE_KINDS.contains(&kind.as_str()) {
                    continue;
                }
                tagged.push((rule.clone(), lint));
            }
        }

        let mut out: Vec<OutLint> = Vec::new();

        // Coach lints first: they carry richer lessons, so on overlap they win.
        if self.config.coach {
            for c in self.coach.check(text) {
                if self.disabled.contains(&c.rule) {
                    continue;
                }
                out.push(OutLint {
                    start: byte_to_utf16(text, c.byte_start),
                    end: byte_to_utf16(text, c.byte_end),
                    original: text[c.byte_start..c.byte_end].to_string(),
                    rule: c.rule,
                    kind: c.kind.to_string(),
                    message: c.message,
                    priority: if c.hint { 90 } else { 10 },
                    suggestions: c.suggestions,
                    description: String::new(),
                    lesson: Some(c.lesson),
                    severity: if c.hint { "hint" } else { "error" },
                });
            }
        }

        // Harper lints sorted by importance, then position.
        tagged.sort_by_key(|(_, l)| (l.span.start, l.priority));

        for (rule, lint) in tagged {
            let start = utf16_at[lint.span.start.min(chars.len())];
            let end = utf16_at[lint.span.end.min(chars.len())];
            if end <= start && !matches!(lint.suggestions.first(), Some(Suggestion::InsertAfter(_))) {
                continue;
            }
            if out.iter().any(|o| o.start < end.max(start + 1) && start < o.end) {
                continue; // overlaps something more specific
            }

            let original: String = chars[lint.span.start..lint.span.end.min(chars.len())]
                .iter()
                .collect();
            if CHAT_WORDS.contains(&original.to_lowercase().as_str()) {
                continue; // deliberate shorthand — leave it alone
            }

            let mut suggestions: Vec<String> = Vec::new();
            for s in &lint.suggestions {
                let rep = match s {
                    Suggestion::ReplaceWith(v) => v.iter().collect::<String>(),
                    Suggestion::InsertAfter(v) => {
                        format!("{}{}", original, v.iter().collect::<String>())
                    }
                    Suggestion::Remove => String::new(),
                };
                if rep != original && !suggestions.contains(&rep) {
                    suggestions.push(rep);
                }
                if suggestions.len() >= 4 {
                    break;
                }
            }

            let kind = lint.lint_kind.to_string_key();
            let severity = if STYLE_KINDS.contains(&kind.as_str()) { "hint" } else { "error" };

            out.push(OutLint {
                description: self.descriptions.get(&rule).cloned().unwrap_or_default(),
                rule,
                kind,
                start,
                end,
                original,
                message: clean_message(&lint.message),
                priority: lint.priority,
                suggestions,
                lesson: None,
                severity,
            });
        }

        out.sort_by_key(|l| (l.start, l.end));
        out
    }

    pub fn is_word_known(&self, word: &str) -> bool {
        let chars: Vec<char> = word.chars().collect();
        self.dictionary.contains_word(&chars)
    }
}

fn byte_to_utf16(text: &str, byte: usize) -> usize {
    text[..byte].encode_utf16().count()
}

/// Harper messages are Markdown-flavoured; strip the bits that look noisy in a UI.
fn clean_message(m: &str) -> String {
    m.replace("**", "").replace('`', "\u{201C}").trim().to_string()
}

// ---------------------------------------------------------------------------
// C ABI
// ---------------------------------------------------------------------------

fn to_c(s: String) -> *mut c_char {
    CString::new(s.replace('\0', "")).unwrap_or_default().into_raw()
}

unsafe fn from_c<'a>(p: *const c_char) -> &'a str {
    if p.is_null() {
        return "";
    }
    CStr::from_ptr(p).to_str().unwrap_or("")
}

/// Create an engine from a JSON config. Never returns null.
#[no_mangle]
pub unsafe extern "C" fn inkling_engine_new(config_json: *const c_char) -> *mut Engine {
    let cfg: EngineConfig = serde_json::from_str(from_c(config_json)).unwrap_or_else(|_| EngineConfig {
        coach: true,
        style: true,
        ..Default::default()
    });
    Box::into_raw(Box::new(Engine::new(cfg)))
}

#[no_mangle]
pub unsafe extern "C" fn inkling_engine_free(engine: *mut Engine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

/// Check UTF-8 `text`. Returns a JSON string the caller must free with
/// `inkling_string_free`.
#[no_mangle]
pub unsafe extern "C" fn inkling_engine_check(engine: *mut Engine, text: *const c_char) -> *mut c_char {
    let Some(engine) = engine.as_mut() else {
        return to_c("{\"lints\":[],\"micros\":0}".into());
    };
    let started = std::time::Instant::now();
    let lints = engine.check(from_c(text));
    let result = CheckResult { lints, micros: started.elapsed().as_micros() };
    to_c(serde_json::to_string(&result).unwrap_or_else(|_| "{\"lints\":[],\"micros\":0}".into()))
}

#[no_mangle]
pub unsafe extern "C" fn inkling_engine_is_word_known(engine: *mut Engine, word: *const c_char) -> bool {
    engine.as_ref().map(|e| e.is_word_known(from_c(word))).unwrap_or(false)
}

/// JSON array with every coach lesson (for the lesson library).
#[no_mangle]
pub extern "C" fn inkling_coach_lessons() -> *mut c_char {
    to_c(serde_json::to_string(&coach::all_lessons()).unwrap_or_else(|_| "[]".into()))
}

/// JSON object { ruleName: description } for every Harper rule.
#[no_mangle]
pub unsafe extern "C" fn inkling_engine_rule_descriptions(engine: *mut Engine) -> *mut c_char {
    let Some(engine) = engine.as_ref() else { return to_c("{}".into()) };
    to_c(serde_json::to_string(&engine.descriptions).unwrap_or_else(|_| "{}".into()))
}

#[no_mangle]
pub unsafe extern "C" fn inkling_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn engine() -> Engine {
        Engine::new(EngineConfig {
            coach: true,
                style: true,
            ..Default::default()
        })
    }

    #[test]
    fn finds_basic_errors() {
        let mut e = engine();
        let l = e.check("This is an test of teh system.");
        assert!(l.iter().any(|l| l.original == "an"));
        assert!(l.iter().any(|l| l.original == "teh"));
    }

    #[test]
    fn utf16_offsets() {
        let mut e = engine();
        let text = "😀 This is an test.";
        let l = e.check(text);
        let an = l.iter().find(|l| l.original == "an").unwrap();
        let utf16: Vec<u16> = text.encode_utf16().collect();
        assert_eq!(String::from_utf16(&utf16[an.start..an.end]).unwrap(), "an");
    }

    #[test]
    fn coach_rules() {
        let mut e = engine();
        let l = e.check("I am agree that we should discuss about the informations since 3 years.");
        let rules: Vec<_> = l.iter().map(|l| l.rule.as_str()).collect();
        assert!(rules.contains(&"Coach.AmAgree"), "{rules:?}");
        assert!(rules.contains(&"Coach.DiscussAbout"), "{rules:?}");
        assert!(rules.contains(&"Coach.Uncountable"), "{rules:?}");
        assert!(rules.contains(&"Coach.SinceFor"), "{rules:?}");
    }

    #[test]
    fn chat_words_are_not_typos() {
        let mut e = engine();
        let l = e.check("Yesterday I went to a Costco and thought wtf am I doing here, lol. LOL, BTW it was fine.");
        assert!(l.iter().all(|l| !["wtf", "lol", "LOL", "BTW"].contains(&l.original.as_str())), "{:?}", l.iter().map(|l| (&l.original, &l.rule)).collect::<Vec<_>>());
    }

    #[test]
    fn user_words() {
        let mut e = Engine::new(EngineConfig { user_words: vec!["Okonkwo".into()], ..Default::default() });
        assert!(e.check("Hello Okonkwo, how are you?").iter().all(|l| l.original != "Okonkwo"));
    }
}
