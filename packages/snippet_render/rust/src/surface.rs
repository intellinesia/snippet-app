use std::sync::{Arc, Condvar, Mutex, atomic::AtomicI64, atomic::Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use irondash_engine_context::EngineContext;
use irondash_texture::{SendableTexture, Texture};

use crate::renderer::{Format, Lang, Renderer};

// Android: the texture is a window the render thread posts to directly, so frames
// never touch the platform thread and are copied once, from GPU memory.
#[cfg(target_os = "android")]
mod out {
    use super::*;
    use irondash_texture::NativeWindow;

    pub type Payload = NativeWindow;

    pub struct Window(NativeWindow);
    // ANativeWindow is refcounted and its producer calls are thread-safe.
    unsafe impl Send for Window {}

    #[derive(Default)]
    pub struct Out {
        pub window: Mutex<Option<Window>>,
    }

    pub fn make(engine: i64, out: &Arc<Out>) -> irondash_texture::Result<Texture<Payload>> {
        let t = Texture::<NativeWindow>::new(engine)?;
        *out.window.lock().unwrap() = Some(Window(t.get()));
        Ok(t)
    }

    pub struct Writer {
        out: Arc<Out>,
        window: Option<Window>,
        size: (i32, i32),
    }

    impl Writer {
        pub fn new(out: Arc<Out>) -> Self {
            Self {
                out,
                window: None,
                size: (0, 0),
            }
        }

        pub fn write(&mut self, renderer: &mut Renderer, clock: f32) -> Result<(), String> {
            if self.window.is_none() {
                self.window = self.out.window.lock().unwrap().take();
            }
            let (w, h) = renderer.size();
            let (w, h) = (w as i32, h as i32);
            let Some(win) = self.window.as_ref() else {
                return Ok(());
            };
            if self.size != (w, h) {
                win.0.set_geometry(w, h);
                self.size = (w, h);
            }
            renderer
                .render_with(clock, |data, stride| win.0.post_rgba(w, h, data, stride))
                .map(|_| ())
                .map_err(|e| e.0)
        }

        pub fn posted(&self, _t: &Arc<SendableTexture<Payload>>) {}
    }
}

// Elsewhere Flutter pulls the latest frame on its raster thread. Frames are shared
// by reference and buffers reused, so a pull costs no copy or allocation.
#[cfg(not(target_os = "android"))]
mod out {
    use super::*;
    use irondash_texture::{BoxedPixelData, PayloadProvider, PixelData, PixelDataProvider};

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

    pub fn make(engine: i64, out: &Arc<Out>) -> irondash_texture::Result<Texture<Payload>> {
        Texture::new_with_provider(engine, Arc::new(Provider(out.clone())))
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

        pub fn posted(&mut self, t: &Arc<SendableTexture<Payload>>) {
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
    texture: Mutex<Option<Arc<SendableTexture<out::Payload>>>>,
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
                Ok(Ok(t)) => {
                    let id = t.id();
                    *on_main.texture.lock().unwrap() = Some(t.into_sendable_texture());
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
