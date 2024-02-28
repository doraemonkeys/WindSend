use std::env;

fn main() {
    let target = env::var("TARGET").unwrap();
    if target.ends_with("musl") {
        println!("cargo:rustc-cfg=feature=\"disable-systray-support\"");
    }
}
