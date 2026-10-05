#![allow(dead_code)]
unsafe extern "C" fn log_values(count: usize, mut args: ...) {
    for _ in 0..count { let _: i32 = unsafe { args.arg() }; }
}
