use harper_core::{linting::LintGroup, spell::FstDictionary, Dialect};
fn main() {
    let g = LintGroup::new_curated(FstDictionary::curated(), Dialect::American);
    let d = g.all_descriptions();
    let mut keys: Vec<_> = d.keys().collect(); keys.sort();
    let enabled: Vec<_> = keys.iter().filter(|k| g.config.is_rule_enabled(k)).collect();
    println!("total {} enabled {}", keys.len(), enabled.len());
    for k in ["SpellCheck","AnA","RepeatedWords","SentenceCapitalization","CapitalizePersonalPronouns","TheirToThere","ModalOf","OpenCompounds","LongSentences","Spaces","CorrectNumberSuffix","ItsContraction","Dashes","UnclosedQuotes","Matcher","PronounContraction","AvoidCurses","BoringWords","SpelledNumbers","ExpandTimeShorthands","OxfordComma","NoOxfordComma","PhrasalVerbAsCompoundNoun","EllipsisLength","MergeWords","SplitWords","LetsConfusion","ThenThan","YourYoure","WhoWhom","FewerLess","AffectEffect","LooseLose","PossessiveYour","WasAloud","ToTooToo","NeedToNoun","PronounInflectionBe","SubjectVerbAgreement","ConfusedPronoun"] {
        if let Some(v) = d.get(k) { println!("\n### {k} (on={})\n{v}", g.config.is_rule_enabled(k)); }
    }
    println!("\n\nALL: {}", keys.iter().map(|s| s.to_string()).collect::<Vec<_>>().join(", "));
}
