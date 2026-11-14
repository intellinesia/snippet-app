use std::sync::{Arc, Condvar, Mutex, atomic::AtomicI64, atomic::Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use irondash_engine_context::EngineContext;
use irondash_texture::{
    BoxedPixelData, PayloadProvider, PixelData, PixelFormat, SendableTexture, SimplePixelData,
    Texture,
};

use crate::renderer::{Format, Lang, Renderer};

#[derive(Default)]
struct Frame {
    width: i32,
    height: i32,
    data: Vec<u8>,
}

struct Provider(Arc<Mutex<Frame>>);

impl PayloadProvider<BoxedPixelData> for Provider {
    fn get_payload(&self) -> BoxedPixelData {
        let f = self.0.lock().unwrap();
        SimplePixelData::new_boxed(f.width, f.height, f.data.clone())
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
    texture: Mutex<Option<Arc<SendableTexture<BoxedPixelData>>>>,
    error: Mutex<Option<String>>,
}

/// One shader on its own render thread, drawing into one Flutter texture.
pub struct Surface {
    shared: Arc<Shared>,
    thread: Option<JoinHandle<()>>,
}

fn format() -> Format {
    match PixelData::FORMAT {
        PixelFormat::BGRA => Format::Bgra,
        PixelFormat::RGBA => Format::Rgba,
    }
}

impl Surface {
    pub fn new(engine: i64, source: String, lang: Lang, width: u32, height: u32, fps: u32) -> Self {
        let frame = Arc::new(Mutex::new(Frame::default()));
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
        let provider = Arc::new(Provider(frame.clone()));
        let on_main = shared.clone();
        // Textures are made on the platform thread; Dart may call from another.
        let made =
            EngineContext::perform_on_main_thread(move || {
                match Texture::new_with_provider(engine, provider) {
                    Ok(t) => {
                        let id = t.id();
                        *on_main.texture.lock().unwrap() = Some(t.into_sendable_texture());
                        on_main.texture_id.store(id, Ordering::SeqCst);
                        on_main.wake.notify_all();
                    }
                    Err(e) => *on_main.error.lock().unwrap() = Some(format!("texture: {e:?}")),
                }
            });
        if let Err(e) = made {
            *shared.error.lock().unwrap() = Some(format!("engine context: {e:?}"));
        }
        let worker = shared.clone();
        let thread = std::thread::Builder::new()
            .name("snippet-render".into())
            .spawn(move || run(worker, frame))
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

fn run(shared: Arc<Shared>, frame: Arc<Mutex<Frame>>) {
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
        let (w, h) = renderer.size();
        match renderer.render(clock) {
            Ok(px) => {
                let mut f = frame.lock().unwrap();
                f.width = w as i32;
                f.height = h as i32;
                f.data.clear();
                f.data.extend_from_slice(px);
            }
            Err(e) => return fail(e.0),
        }
        if let Some(t) = shared.texture.lock().unwrap().as_ref() {
            t.mark_frame_available();
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
