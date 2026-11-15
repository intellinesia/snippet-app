use std::{cell::RefCell, marker::PhantomData, slice, sync::Arc};

use irondash_engine_context::EngineContext;
use jni::{
    JNIEnv,
    objects::{GlobalRef, JObject, JString, JValue},
};
use ndk_sys::{
    AHardwareBuffer_Format, ANativeWindow, ANativeWindow_Buffer, ANativeWindow_acquire,
    ANativeWindow_fromSurface, ANativeWindow_lock, ANativeWindow_release,
    ANativeWindow_setBuffersGeometry, ANativeWindow_unlockAndPost,
};

use crate::{
    BoxedPixelData, Error, PayloadProvider, PixelFormat, PlatformTextureWithProvider,
    PlatformTextureWithoutProvider, Result, log::OkLog,
};

// A JNI call that throws leaves the exception pending; returning to the looper
// with it pending crashes the app, so clear it and keep its stack as the error.
fn take_exception(env: &mut JNIEnv) -> Option<String> {
    if !env.exception_check().unwrap_or(false) {
        return None;
    }
    let ex = env.exception_occurred().ok();
    env.exception_clear().ok();
    let text = ex.and_then(|ex| {
        let v = env
            .call_static_method(
                "android/util/Log",
                "getStackTraceString",
                "(Ljava/lang/Throwable;)Ljava/lang/String;",
                &[JValue::Object(&ex)],
            )
            .and_then(|v| v.l())
            .ok()?;
        env.get_string(&JString::from(v)).ok().map(String::from)
    });
    env.exception_clear().ok();
    Some(text.unwrap_or_else(|| "Java exception".into()))
}

#[derive(PartialEq, Eq, Clone, Copy)]
struct Geometry {
    width: i32,
    height: i32,
    format: i32,
}

pub struct PlatformTexture<Type> {
    id: i64,
    texture_entry: GlobalRef,
    surface: GlobalRef,
    native_window: *mut ANativeWindow,
    last_geometry: RefCell<Option<Geometry>>,
    pixel_data_provider: Option<Arc<dyn PayloadProvider<BoxedPixelData>>>,
    _phantom: PhantomData<Type>,
}

pub(crate) const PIXEL_DATA_FORMAT: PixelFormat = PixelFormat::RGBA;

impl<Type> PlatformTexture<Type> {
    pub fn id(&self) -> i64 {
        self.id
    }

    fn new(
        engine_handle: i64,
        pixel_buffer_provider: Option<Arc<dyn PayloadProvider<BoxedPixelData>>>,
    ) -> Result<Self> {
        let java_vm = EngineContext::get_java_vm()?;
        let mut env = java_vm.attach_current_thread()?;
        env.push_local_frame(16)?;
        let res = match Self::create(&mut env, engine_handle, pixel_buffer_provider) {
            Err(e) => Err(take_exception(&mut env).map_or(e, Error::JavaException)),
            ok => ok,
        };
        unsafe { env.pop_local_frame(&JObject::null()) }.ok();
        res
    }

    fn create(
        env: &mut JNIEnv,
        engine_handle: i64,
        pixel_buffer_provider: Option<Arc<dyn PayloadProvider<BoxedPixelData>>>,
    ) -> Result<Self> {
        let engine_context = EngineContext::get()?;
        let texture_registry = engine_context.get_texture_registry(engine_handle)?;
        let texture_entry = env
            .call_method(
                texture_registry.as_obj(),
                "createSurfaceTexture",
                "()Lio/flutter/view/TextureRegistry$SurfaceTextureEntry;",
                &[],
            )?
            .l()?;
        let surface_texture = env
            .call_method(
                &texture_entry,
                "surfaceTexture",
                "()Landroid/graphics/SurfaceTexture;",
                &[],
            )?
            .l()?;
        let surface = env.new_object(
            "android/view/Surface",
            "(Landroid/graphics/SurfaceTexture;)V",
            &[(&surface_texture).into()],
        )?;
        let native_window =
            unsafe { ANativeWindow_fromSurface(env.get_native_interface(), surface.as_raw()) };
        if native_window.is_null() {
            return Err(Error::TextureRegistrationFailed);
        }
        let id = env.call_method(&texture_entry, "id", "()J", &[])?.j()?;
        Ok(Self {
            id,
            texture_entry: env.new_global_ref(texture_entry)?,
            surface: env.new_global_ref(surface)?,
            native_window,
            last_geometry: RefCell::new(None),
            pixel_data_provider: pixel_buffer_provider,
            _phantom: PhantomData {},
        })
    }

    fn destroy(&mut self) -> Result<()> {
        let java_vm = EngineContext::get_java_vm()?;
        let mut env = java_vm.attach_current_thread()?;
        let released = env.call_method(self.texture_entry.as_obj(), "release", "()V", &[]);
        unsafe {
            ANativeWindow_release(self.native_window);
        }
        if released.is_err() {
            if let Some(e) = take_exception(&mut env) {
                return Err(Error::JavaException(e));
            }
        }
        released?;
        Ok(())
    }

    pub fn mark_frame_available(&self) -> Result<()> {
        if let Some(provider) = self.pixel_data_provider.as_ref() {
            let payload = provider.get_payload();
            let payload = payload.get();
            let geometry = Geometry {
                width: payload.width,
                height: payload.height,
                format: AHardwareBuffer_Format::AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM.0 as i32,
            };
            let mut last_geometry = self.last_geometry.borrow_mut();
            if *last_geometry != Some(geometry) {
                unsafe {
                    ANativeWindow_setBuffersGeometry(
                        self.native_window,
                        geometry.width,
                        geometry.height,
                        geometry.format,
                    );
                }
                last_geometry.replace(geometry);
            }
            let mut buf: ANativeWindow_Buffer = unsafe { std::mem::zeroed() };
            // A failed lock leaves `bits` null; upstream asserted here and aborted the app.
            let locked = unsafe {
                ANativeWindow_lock(self.native_window, &mut buf as *mut _, std::ptr::null_mut())
            };
            if locked != 0 || buf.bits.is_null() {
                return Ok(());
            }
            let rows = buf.height.min(payload.height).max(0) as usize;
            let dst_stride = buf.stride.max(0) as usize * 4;
            let src_stride = payload.width.max(0) as usize * 4;
            let row_bytes = src_stride.min(buf.width.max(0) as usize * 4);
            let data = unsafe {
                slice::from_raw_parts_mut(buf.bits as *mut u8, buf.height as usize * dst_stride)
            };
            for y in 0..rows {
                let (src, dst) = (y * src_stride, y * dst_stride);
                if src + row_bytes > payload.data.len() {
                    break;
                }
                data[dst..dst + row_bytes].copy_from_slice(&payload.data[src..src + row_bytes]);
            }

            unsafe { ANativeWindow_unlockAndPost(self.native_window) };
        }
        Ok(())
    }
}

impl<Type> Drop for PlatformTexture<Type> {
    fn drop(&mut self) {
        self.destroy().ok_log();
    }
}

impl PlatformTextureWithProvider for BoxedPixelData {
    fn create_texture(
        engine_handle: i64,
        payload_provider: Arc<dyn PayloadProvider<Self>>,
    ) -> Result<PlatformTexture<BoxedPixelData>> {
        PlatformTexture::new(engine_handle, Some(payload_provider))
    }
}

pub struct NativeWindow {
    native_window: *mut ANativeWindow,
}

impl NativeWindow {
    fn new(native_window: *mut ANativeWindow) -> Self {
        unsafe { ANativeWindow_acquire(native_window) };
        Self { native_window }
    }

    pub fn get_native_window(&self) -> *mut ANativeWindow {
        self.native_window
    }

    /// Sizes the window's buffers; only call when the size changes.
    pub fn set_geometry(&self, width: i32, height: i32) {
        unsafe {
            ANativeWindow_setBuffersGeometry(
                self.native_window,
                width,
                height,
                AHardwareBuffer_Format::AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM.0 as i32,
            );
        }
    }

    /// Copies RGBA rows `stride` bytes apart into the next buffer and posts it.
    /// Safe from any thread: the window is the producer end of a buffer queue.
    pub fn post_rgba(&self, width: i32, height: i32, src: &[u8], stride: usize) -> bool {
        let mut buf: ANativeWindow_Buffer = unsafe { std::mem::zeroed() };
        let locked = unsafe {
            ANativeWindow_lock(self.native_window, &mut buf as *mut _, std::ptr::null_mut())
        };
        if locked != 0 || buf.bits.is_null() {
            return false;
        }
        let rows = buf.height.min(height).max(0) as usize;
        let dst_stride = buf.stride.max(0) as usize * 4;
        let row_bytes = buf.width.min(width).max(0) as usize * 4;
        let dst = unsafe {
            slice::from_raw_parts_mut(buf.bits as *mut u8, buf.height.max(0) as usize * dst_stride)
        };
        for y in 0..rows {
            let s = y * stride;
            if s + row_bytes > src.len() {
                break;
            }
            dst[y * dst_stride..y * dst_stride + row_bytes].copy_from_slice(&src[s..s + row_bytes]);
        }
        unsafe { ANativeWindow_unlockAndPost(self.native_window) };
        true
    }
}

impl Clone for NativeWindow {
    fn clone(&self) -> Self {
        Self::new(self.native_window)
    }
}

impl Drop for NativeWindow {
    fn drop(&mut self) {
        unsafe {
            ANativeWindow_release(self.native_window);
        }
    }
}

impl PlatformTextureWithoutProvider for NativeWindow {
    fn create_texture(engine_handle: i64) -> Result<PlatformTexture<NativeWindow>> {
        PlatformTexture::new(engine_handle, None)
    }

    fn get(texture: &PlatformTexture<Self>) -> Self {
        Self::new(texture.native_window)
    }
}

/// Flutter's ImageReader-backed texture. Impeller samples its buffers directly;
/// a SurfaceTexture on Vulkan costs a GL copy and a fence wait every frame.
pub struct SurfaceProducer {
    id: i64,
    entry: GlobalRef,
}

impl SurfaceProducer {
    /// Call on the platform thread.
    pub fn new(engine_handle: i64) -> Result<Self> {
        let java_vm = EngineContext::get_java_vm()?;
        let mut env = java_vm.attach_current_thread()?;
        env.push_local_frame(8)?;
        let res = (|| -> Result<Self> {
            let registry = EngineContext::get()?.get_texture_registry(engine_handle)?;
            let entry = env
                .call_method(
                    registry.as_obj(),
                    "createSurfaceProducer",
                    "()Lio/flutter/view/TextureRegistry$SurfaceProducer;",
                    &[],
                )?
                .l()?;
            let id = env.call_method(&entry, "id", "()J", &[])?.j()?;
            Ok(Self {
                id,
                entry: env.new_global_ref(entry)?,
            })
        })();
        let res = match res {
            Err(e) => Err(take_exception(&mut env).map_or(e, Error::JavaException)),
            ok => ok,
        };
        unsafe { env.pop_local_frame(&JObject::null()) }.ok();
        res
    }

    pub fn id(&self) -> i64 {
        self.id
    }

    /// Sizes the buffers and returns the window to draw into. Resizing replaces
    /// the window, so call again after every size change.
    pub fn window(&self, width: i32, height: i32) -> Result<NativeWindow> {
        let java_vm = EngineContext::get_java_vm()?;
        let mut env = java_vm.attach_current_thread()?;
        env.push_local_frame(8)?;
        let res = (|| -> Result<NativeWindow> {
            env.call_method(
                self.entry.as_obj(),
                "setSize",
                "(II)V",
                &[JValue::Int(width), JValue::Int(height)],
            )?;
            let surface = env
                .call_method(
                    self.entry.as_obj(),
                    "getSurface",
                    "()Landroid/view/Surface;",
                    &[],
                )?
                .l()?;
            let raw =
                unsafe { ANativeWindow_fromSurface(env.get_native_interface(), surface.as_raw()) };
            if raw.is_null() {
                return Err(Error::TextureRegistrationFailed);
            }
            // fromSurface returned an owned reference; NativeWindow takes its own.
            let window = NativeWindow::new(raw);
            unsafe { ANativeWindow_release(raw) };
            Ok(window)
        })();
        let res = match res {
            Err(e) => Err(take_exception(&mut env).map_or(e, Error::JavaException)),
            ok => ok,
        };
        unsafe { env.pop_local_frame(&JObject::null()) }.ok();
        res
    }
}

impl Drop for SurfaceProducer {
    fn drop(&mut self) {
        let Ok(java_vm) = EngineContext::get_java_vm() else {
            return;
        };
        let Ok(mut env) = java_vm.attach_current_thread() else {
            return;
        };
        if env
            .call_method(self.entry.as_obj(), "release", "()V", &[])
            .is_err()
        {
            take_exception(&mut env);
        }
    }
}

pub struct Surface(pub GlobalRef);

impl PlatformTextureWithoutProvider for Surface {
    fn create_texture(engine_handle: i64) -> Result<PlatformTexture<Surface>> {
        PlatformTexture::new(engine_handle, None)
    }

    fn get(texture: &PlatformTexture<Self>) -> Self {
        Self(texture.surface.clone())
    }
}
