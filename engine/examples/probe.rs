use inkling_engine::*;
use std::time::Instant;
fn main() {
    let t = Instant::now();
    let mut e = Engine::new(serde_json::from_str(r#"{"coach":true,"falseFriends":true,"style":true}"#).unwrap());
    eprintln!("init {:?}", t.elapsed());
    let texts = [
        "Hi Tom, i think their is a problem with the the invoice. Its not correct and we should of checked it earlier.",
        "I recieve alot of emails every day, and I dont have time to answer them all. This is an big problem for me.",
        "Ahoj, jak se máš? Dneska jsem byl v práci a bylo to dobré.",
        "Ahoj jak se mas, dneska jsem byl v praci",
        "Me and him went to the store yesterday, but they was closed. Could you please send me the actual version of the document?",
    ];
    for txt in texts {
        let t = Instant::now();
        let l = e.check(txt);
        let d = t.elapsed();
        println!("\n## {txt}\n   ({:?})", d);
        for l in l { println!("  [{}|{}|{}] {:?} -> {:?} :: {}", l.rule, l.kind, l.severity, l.original, l.suggestions, l.message); }
    }
    let long = texts[0].repeat(200);
    let t = Instant::now(); let n = e.check(&long).len(); println!("\nlong {} chars: {} lints in {:?}", long.len(), n, t.elapsed());
    let t = Instant::now(); let n = e.check(&long).len(); println!("long again (cached): {} lints in {:?}", n, t.elapsed());
}
