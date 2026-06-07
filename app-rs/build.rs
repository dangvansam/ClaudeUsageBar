fn main() {
    #[cfg(target_os = "windows")]
    {
        let _ = embed_resource::compile("app.rc", embed_resource::NONE);
        println!("cargo:rerun-if-changed=app.rc");
        println!("cargo:rerun-if-changed=app.manifest");
    }
}
