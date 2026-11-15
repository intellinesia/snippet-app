use std::sync::{Arc, Condvar, Mutex, atomic::AtomicI64, atomic::Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use irondash_engine_context::EngineContext;

use crate::renderer::{Format, Lang, Renderer};

// Android: the render thread draws straight into the buffers Flutter composites,
// through a Vulkan swapchain on a SurfaceProducer window. Nothing is read back
// or copied, and the platform thread is never involved.
#[cfg(target_os = "android")]
mod out {
    use super::*;
    use irondash_texture::{NativeWindow, SurfaceProducer};
    use std::ptr::NonNull;
    use wgpu::rwh::{AndroidNdkWindowHandle, RawWindowHandle};

    #[link(name = "log")]
    unsafe extern "C" {
        fn __android_log_write(
            prio: i32,
            tag: *const std::ffi::c_char,
            text: *const std::ffi::c_char,
        ) -> i32;
    }

    fn log(text: &str) {
        let text = std::ffi::CString::new(text).unwrap_or_default();
        unsafe { __android_log_write(4, c"snippet_render".as_ptr(), text.as_ptr()) };
    }

    // ANativeWindow is refcounted and its producer calls are thread-safe.
    struct Window(NativeWindow);
    unsafe impl Send for Window {}

    /// Keeps the texture registered; Flutter only releases it on the platform thread.
    pub struct Handle(Option<Arc<SurfaceProducer>>);

    impl Drop for Handle {
        fn drop(&mut self) {
            if let Some(p) = self.0.take() {
                let _ = EngineContext::perform_on_main_thread(move || drop(p));
            }
        }
    }

    #[derive(Default)]
    pub struct Out {
        producer: Mutex<Option<Arc<SurfaceProducer>>>,
    }

    pub fn make(engine: i64, out: &Arc<Out>) -> irondash_texture::Result<(i64, Handle)> {
        let p = Arc::new(SurfaceProducer::new(engine)?);
        *out.producer.lock().unwrap() = Some(p.clone());
        Ok((p.id(), Handle(Some(p))))
    }

    pub struct Writer {
        out: Arc<Out>,
        producer: Option<Arc<SurfaceProducer>>,
        size: (u32, u32),
        // Set when the GPU cannot present to the window: copy frames in on the CPU.
        cpu: Option<Window>,
    }

    impl Writer {
        pub fn new(out: Arc<Out>) -> Self {
            Self {
                out,
                producer: None,
                size: (0, 0),
                cpu: None,
            }
        }

        fn attach(&mut self, renderer: &mut Renderer) -> Result<(), String> {
            let Some(p) = self.producer.as_ref() else {
                return Ok(());
            };
            let (w, h) = renderer.size();
            let win = p
                .window(w as i32, h as i32)
                .map_err(|e| format!("window: {e}"))?;
            let ptr = NonNull::new(win.get_native_window().cast()).ok_or("window: null")?;
            let handle = RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(ptr));
            let keep = Box::new(Window(win.clone()));
            let attached = unsafe { renderer.attach(handle, keep) };
            log(&format!(
                "{} {w}x{h}: {:?}",
                renderer.backend(),
                attached.as_ref().map(|_| "direct present")
            ));
            match attached {
                Ok(()) => self.cpu = None,
                Err(_) => {
                    renderer.detach();
                    win.set_geometry(w as i32, h as i32);
                    self.cpu = Some(Window(win));
                }
            }
            self.size = (w, h);
            Ok(())
        }

        pub fn write(&mut self, renderer: &mut Renderer, clock: f32) -> Result<(), String> {
            if self.producer.is_none() {
                self.producer = self.out.producer.lock().unwrap().take();
                if self.producer.is_none() {
                    return Ok(());
                }
            }
            if self.size != renderer.size() {
                self.attach(renderer)?;
            }
            if let Some(win) = self.cpu.as_ref() {
                let (w, h) = self.size;
                return renderer
                    .render_with(clock, |data, stride| {
                        win.0.post_rgba(w as i32, h as i32, data, stride)
                    })
                    .map(|_| ())
                    .map_err(|e| e.0);
            }
            renderer.present(clock).map(|_| ()).map_err(|e| e.0)
        }

        pub fn posted(&mut self, _t: &Handle) {}
    }
}

// Elsewhere Flutter pulls the latest frame on its raster thread. Frames are shared
// by reference and buffers reused, so a pull costs no copy or allocation.
#[cfg(not(target_os = "android"))]
mod out {
    use super::*;
    use irondash_texture::{
        BoxedPixelData, PayloadProvider, PixelData, PixelDataProvider, SendableTexture, Texture,
    };

    pub type Payload = BoxedPixelData;

    #[derive(Default, Clone)]
    struct Frame {
        width: i32,
        height: i32,
        data: Arc<Vec<u8>>,
    }

    impl PixelDataProvider for Frame {
        fn get(&self) -> PixelData<'_> {
            PixelData {
                width: self.width,
                height: self.height,
                data: &self.data,
            }
        }
    }

    #[derive(Default)]
    pub struct Out {
        front: Mutex<Frame>,
    }

    struct Provider(Arc<Out>);

    impl PayloadProvider<BoxedPixelData> for Provider {
        fn get_payload(&self) -> BoxedPixelData {
            Box::new(self.0.front.lock().unwrap().clone())
        }
    }

    pub type Handle = Arc<SendableTexture<Payload>>;

    pub fn make(engine: i64, out: &Arc<Out>) -> irondash_texture::Result<(i64, Handle)> {
        let t = Texture::new_with_provider(engine, Arc::new(Provider(out.clone())))?;
        Ok((t.id(), t.into_sendable_texture()))
    }

    pub struct Writer {
        out: Arc<Out>,
        back: Arc<Vec<u8>>,
        fresh: bool,
    }

    impl Writer {
        pub fn new(out: Arc<Out>) -> Self {
            Self {
                out,
                back: Arc::default(),
                fresh: false,
            }
        }

        pub fn write(&mut self, renderer: &mut Renderer, clock: f32) -> Result<(), String> {
            let (w, h) = renderer.size();
            let tight = w as usize * 4;
            // Reuse the buffer unless Flutter still holds it from the last pull.
            if Arc::get_mut(&mut self.back).is_none() {
                self.back = Arc::default();
            }
            let back = Arc::get_mut(&mut self.back).unwrap();
            let done = renderer
                .render_with(clock, |data, stride| {
                    back.clear();
                    for y in 0..h as usize {
                        back.extend_from_slice(&data[y * stride..y * stride + tight]);
                    }
                })
                .map_err(|e| e.0)?;
            if done.is_some() {
                let mut f = self.out.front.lock().unwrap();
                (f.width, f.height) = (w as i32, h as i32);
                std::mem::swap(&mut f.data, &mut self.back);
                self.fresh = true;
            }
            Ok(())
        }

        pub fn posted(&mut self, t: &Handle) {
            if std::mem::take(&mut self.fresh) {
                t.mark_frame_available();
            }
        }
    }
}

fn format() -> Format {
    match irondash_texture::PixelData::FORMAT {
        irondash_texture::PixelFormat::BGRA => Format::Bgra,
        irondash_texture::PixelFormat::RGBA => Format::Rgba,
    }
}

struct Command {
    shader: Option<(String, Lang)>,
    width: u32,
    height: u32,
    fps: u32,
    paused: bool,
    dirty: bool,
    stop: bool,
}

struct Shared {
    cmd: Mutex<Command>,
    wake: Condvar,
    texture_id: AtomicI64,
    texture: Mutex<Option<out::Handle>>,
    error: Mutex<Option<String>>,
}

/// One shader on its own render thread, drawing into one Flutter texture.
pub struct Surface {
    shared: Arc<Shared>,
    thread: Option<JoinHandle<()>>,
}

impl Surface {
    pub fn new(engine: i64, source: String, lang: Lang, width: u32, height: u32, fps: u32) -> Self {
        let out = Arc::new(out::Out::default());
        let shared = Arc::new(Shared {
            cmd: Mutex::new(Command {
                shader: Some((source, lang)),
                width: row_aligned(width),
                height: height.max(1),
                fps: fps.clamp(1, 60),
                paused: false,
                dirty: true,
                stop: false,
            }),
            wake: Condvar::new(),
            texture_id: AtomicI64::new(-1),
            texture: Mutex::new(None),
            error: Mutex::new(None),
        });
        let on_main = shared.clone();
        let made_out = out.clone();
        // Textures are made on the platform thread; Dart may call from another.
        let made = EngineContext::perform_on_main_thread(move || {
            let made = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                out::make(engine, &made_out)
            }));
            match made {
                Err(_) => *on_main.error.lock().unwrap() = Some("texture: panicked".into()),
                Ok(Ok((id, handle))) => {
                    *on_main.texture.lock().unwrap() = Some(handle);
                    on_main.texture_id.store(id, Ordering::SeqCst);
                    on_main.wake.notify_all();
                }
                Ok(Err(e)) => *on_main.error.lock().unwrap() = Some(format!("texture: {e}")),
            }
        });
        if let Err(e) = made {
            *shared.error.lock().unwrap() = Some(format!("engine context: {e:?}"));
        }
        let worker = shared.clone();
        let thread = std::thread::Builder::new()
            .name("snippet-render".into())
            .spawn(move || run(worker, out::Writer::new(out)))
            .ok();
        Self { shared, thread }
    }

    pub fn texture_id(&self) -> i64 {
        self.shared.texture_id.load(Ordering::SeqCst)
    }

    pub fn error(&self) -> Option<String> {
        self.shared.error.lock().unwrap().clone()
    }

    fn update(&self, f: impl FnOnce(&mut Command)) {
        let mut cmd = self.shared.cmd.lock().unwrap();
        f(&mut cmd);
        cmd.dirty = true;
        self.shared.wake.notify_all();
    }

    pub fn set_shader(&self, source: String, lang: Lang) {
        self.update(|c| c.shader = Some((source, lang)));
    }

    pub fn resize(&self, width: u32, height: u32) {
        self.update(|c| (c.width, c.height) = (row_aligned(width), height.max(1)));
    }

    pub fn set_paused(&self, paused: bool) {
        self.update(|c| c.paused = paused);
    }

    pub fn set_fps(&self, fps: u32) {
        self.update(|c| c.fps = fps.clamp(1, 60));
    }
}

impl Drop for Surface {
    fn drop(&mut self) {
        self.update(|c| c.stop = true);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

fn run(shared: Arc<Shared>, mut writer: out::Writer) {
    let fail = |e: String| *shared.error.lock().unwrap() = Some(e);
    let (source, lang, width, height) = {
        let mut cmd = shared.cmd.lock().unwrap();
        let (s, l) = cmd.shader.take().unwrap();
        (s, l, cmd.width, cmd.height)
    };
    let mut renderer = match Renderer::new(&source, lang, format(), width, height) {
        Ok(r) => r,
        Err(e) => return fail(e.0),
    };
    // Time only advances while running, so a paused scene resumes where it was.
    let mut clock = 0f32;
    let mut last = Instant::now();
    loop {
        let (fps, paused) = {
            let mut cmd = shared.cmd.lock().unwrap();
            while !cmd.stop && cmd.paused && !cmd.dirty {
                cmd = shared.wake.wait(cmd).unwrap();
                last = Instant::now();
            }
            if cmd.stop {
                return;
            }
            if let Some((s, l)) = cmd.shader.take()
                && let Err(e) = renderer.set_shader(&s, l)
            {
                fail(e.0);
            }
            renderer.resize(cmd.width, cmd.height);
            cmd.dirty = false;
            (cmd.fps, cmd.paused)
        };
        let started = Instant::now();
        if !paused {
            clock += started.duration_since(last).as_secs_f32();
        }
        last = started;
        if let Err(e) = writer.write(&mut renderer, clock) {
            return fail(e);
        }
        if let Some(t) = shared.texture.lock().unwrap().as_ref() {
            writer.posted(t);
        }
        let budget = Duration::from_secs_f32(1.0 / fps as f32);
        let cmd = shared.cmd.lock().unwrap();
        let wait = budget.saturating_sub(started.elapsed());
        let _ = shared
            .wake
            .wait_timeout_while(cmd, wait, |c| !c.stop && !c.dirty);
    }
}

// macOS wraps frames in an IOSurface with bytesPerRow = width * 4; Metal rejects unaligned rows.
fn row_aligned(width: u32) -> u32 {
    width.max(1).div_ceil(16) * 16
}
