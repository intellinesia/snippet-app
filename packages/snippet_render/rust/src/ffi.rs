use std::ffi::{CStr, CString, c_char};

use crate::renderer::{Lang, compile};
use crate::surface::Surface;

fn lang(code: i32) -> Lang {
    if code == 1 { Lang::Glsl } else { Lang::Wgsl }
}

unsafe fn text(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

fn owned(s: Option<String>) -> *mut c_char {
    s.and_then(|s| CString::new(s.replace('\0', " ")).ok())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}

/// Null when the shader compiles, else the compiler's message.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_check(source: *const c_char, lang_code: i32) -> *mut c_char {
    owned(compile(&unsafe { text(source) }, lang(lang_code)).err().map(|e| e.0))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_create(
    engine: i64,
    source: *const c_char,
    lang_code: i32,
    width: u32,
    height: u32,
    fps: u32,
) -> *mut Surface {
    let s = Surface::new(engine, unsafe { text(source) }, lang(lang_code), width, height, fps);
    Box::into_raw(Box::new(s))
}

/// -1 until the platform thread has registered the texture.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_texture_id(s: *mut Surface) -> i64 {
    unsafe { s.as_ref() }.map_or(-1, Surface::texture_id)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_error(s: *mut Surface) -> *mut c_char {
    owned(unsafe { s.as_ref() }.and_then(Surface::error))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_set_shader(s: *mut Surface, source: *const c_char, lang_code: i32) {
    if let Some(s) = unsafe { s.as_ref() } {
        s.set_shader(unsafe { text(source) }, lang(lang_code));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_resize(s: *mut Surface, width: u32, height: u32) {
    if let Some(s) = unsafe { s.as_ref() } {
        s.resize(width, height);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_set_paused(s: *mut Surface, paused: bool) {
    if let Some(s) = unsafe { s.as_ref() } {
        s.set_paused(paused);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_set_fps(s: *mut Surface, fps: u32) {
    if let Some(s) = unsafe { s.as_ref() } {
        s.set_fps(fps);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_destroy(s: *mut Surface) {
    if !s.is_null() {
        drop(unsafe { Box::from_raw(s) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sr_free_string(p: *mut c_char) {
    if !p.is_null() {
        drop(unsafe { CString::from_raw(p) });
    }
}
