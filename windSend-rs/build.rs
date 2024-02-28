use std::env;

fn main() {
    let target = env::var("TARGET").unwrap();
    if target.ends_with("musl") {
        println!("disable_select_file: true");
        println!("cargo:rustc-cfg=feature=\"disable_select_file\"");
    }
}
