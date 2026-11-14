use std::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lang {
    Wgsl,
    Glsl,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    Rgba,
    Bgra,
}

#[derive(Debug)]
pub struct Error(pub String);

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

const VERTEX: &str = r#"
@vertex
fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
    let p = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    return vec4<f32>(p * 2.0 - 1.0, 0.0, 1.0);
}
"#;

// A shader supplies `main_image(frag) -> vec4` with `u.time` and
// `u.resolution`; frag is in pixels with y up, as in Shadertoy.
const WGSL_PRELUDE: &str = r#"
struct Globals { resolution: vec2<f32>, time: f32, pad: f32 };
@group(0) @binding(0) var<uniform> u: Globals;
"#;

const WGSL_ENTRY: &str = r#"
@fragment
fn fs(@builtin(position) p: vec4<f32>) -> @location(0) vec4<f32> {
    return main_image(vec2<f32>(p.x, u.resolution.y - p.y));
}
"#;

// Shadertoy names: mainImage, iTime, iResolution.
const GLSL_PRELUDE: &str = "#version 450
layout(set = 0, binding = 0) uniform Globals { vec2 iResolution2; float iTime; float iPad; };
layout(location = 0) out vec4 snippetOut;
#define iResolution vec3(iResolution2, 1.0)
#line 1
";

const GLSL_ENTRY: &str = "
void main() {
    vec4 c = vec4(0.0);
    mainImage(c, vec2(gl_FragCoord.x, iResolution2.y - gl_FragCoord.y));
    snippetOut = c;
}
";

pub fn wrap(source: &str, lang: Lang) -> String {
    match lang {
        Lang::Wgsl => format!("{WGSL_PRELUDE}{source}\n{WGSL_ENTRY}"),
        Lang::Glsl => format!("{GLSL_PRELUDE}{source}\n{GLSL_ENTRY}"),
    }
}

/// Parses and validates without a GPU, so errors read like a compiler's.
pub fn compile(source: &str, lang: Lang) -> Result<naga::Module, Error> {
    let code = wrap(source, lang);
    let module = match lang {
        Lang::Wgsl => naga::front::wgsl::parse_str(&code)
            .map_err(|e| Error(e.emit_to_string(source)))?,
        Lang::Glsl => {
            let opts = naga::front::glsl::Options::from(naga::ShaderStage::Fragment);
            naga::front::glsl::Frontend::default()
                .parse(&opts, &code)
                .map_err(|e| Error(e.emit_to_string(&code)))?
        }
    };
    naga::valid::Validator::new(
        naga::valid::ValidationFlags::all(),
        naga::valid::Capabilities::empty(),
    )
    .validate(&module)
    .map_err(|e| Error(e.emit_to_string(&code)))?;
    Ok(module)
}

pub struct Renderer {
    device: wgpu::Device,
    queue: wgpu::Queue,
    vertex: wgpu::ShaderModule,
    layout: wgpu::PipelineLayout,
    bind_group: wgpu::BindGroup,
    uniforms: wgpu::Buffer,
    pipeline: wgpu::RenderPipeline,
    format: wgpu::TextureFormat,
    target: wgpu::Texture,
    readback: wgpu::Buffer,
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

fn padded_row(width: u32) -> u32 {
    let row = width * 4;
    let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
    row.div_ceil(align) * align
}

impl Renderer {
    pub fn new(
        source: &str,
        lang: Lang,
        format: Format,
        width: u32,
        height: u32,
    ) -> Result<Self, Error> {
        let module = compile(source, lang)?;
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle_from_env());
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            ..Default::default()
        }))
        .map_err(|e| Error(format!("no GPU adapter: {e}")))?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("snippet_render"),
            required_limits: wgpu::Limits::downlevel_webgl2_defaults()
                .using_resolution(adapter.limits()),
            ..Default::default()
        }))
        .map_err(|e| Error(format!("no GPU device: {e}")))?;
        let vertex = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("vertex"),
            source: wgpu::ShaderSource::Wgsl(VERTEX.into()),
        });
        let bind_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[Some(&bind_layout)],
            immediate_size: 0,
        });
        let uniforms = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("globals"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &bind_layout,
            entries: &[wgpu::BindGroupEntry { binding: 0, resource: uniforms.as_entire_binding() }],
        });
        let format = match format {
            Format::Rgba => wgpu::TextureFormat::Rgba8Unorm,
            Format::Bgra => wgpu::TextureFormat::Bgra8Unorm,
        };
        let pipeline = Self::pipeline(&device, &vertex, &layout, format, module, lang)?;
        let (target, readback) = Self::targets(&device, format, width, height);
        Ok(Self {
            device,
            queue,
            vertex,
            layout,
            bind_group,
            uniforms,
            pipeline,
            format,
            target,
            readback,
            width,
            height,
            pixels: vec![0; (width * height * 4) as usize],
        })
    }

    fn pipeline(
        device: &wgpu::Device,
        vertex: &wgpu::ShaderModule,
        layout: &wgpu::PipelineLayout,
        format: wgpu::TextureFormat,
        module: naga::Module,
        lang: Lang,
    ) -> Result<wgpu::RenderPipeline, Error> {
        let fragment = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("fragment"),
            source: wgpu::ShaderSource::Naga(std::borrow::Cow::Owned(module)),
        });
        let entry = match lang {
            Lang::Wgsl => "fs",
            Lang::Glsl => "main",
        };
        let scope = device.push_error_scope(wgpu::ErrorFilter::Validation);
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("shader"),
            layout: Some(layout),
            vertex: wgpu::VertexState {
                module: vertex,
                entry_point: Some("vs"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &fragment,
                entry_point: Some(entry),
                targets: &[Some(format.into())],
                compilation_options: Default::default(),
            }),
            primitive: Default::default(),
            depth_stencil: None,
            multisample: Default::default(),
            multiview_mask: None,
            cache: None,
        });
        if let Some(e) = pollster::block_on(scope.pop()) {
            return Err(Error(e.to_string()));
        }
        Ok(pipeline)
    }

    fn targets(
        device: &wgpu::Device,
        format: wgpu::TextureFormat,
        width: u32,
        height: u32,
    ) -> (wgpu::Texture, wgpu::Buffer) {
        let target = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("target"),
            size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("readback"),
            size: (padded_row(width) * height) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        (target, readback)
    }

    pub fn set_shader(&mut self, source: &str, lang: Lang) -> Result<(), Error> {
        let module = compile(source, lang)?;
        self.pipeline =
            Self::pipeline(&self.device, &self.vertex, &self.layout, self.format, module, lang)?;
        Ok(())
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        let (width, height) = (width.max(1), height.max(1));
        if (width, height) == (self.width, self.height) {
            return;
        }
        (self.target, self.readback) = Self::targets(&self.device, self.format, width, height);
        self.width = width;
        self.height = height;
        self.pixels = vec![0; (width * height * 4) as usize];
    }

    pub fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    /// Draws one frame at `time` seconds and returns tightly packed pixels.
    pub fn render(&mut self, time: f32) -> Result<&[u8], Error> {
        let globals = [self.width as f32, self.height as f32, time, 0.0];
        let bytes: Vec<u8> = globals.iter().flat_map(|f| f.to_ne_bytes()).collect();
        self.queue.write_buffer(&self.uniforms, 0, &bytes);
        let view = self.target.create_view(&Default::default());
        let mut enc = self.device.create_command_encoder(&Default::default());
        {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.bind_group, &[]);
            pass.draw(0..3, 0..1);
        }
        let row = padded_row(self.width);
        enc.copy_texture_to_buffer(
            self.target.as_image_copy(),
            wgpu::TexelCopyBufferInfo {
                buffer: &self.readback,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(row),
                    rows_per_image: None,
                },
            },
            wgpu::Extent3d { width: self.width, height: self.height, depth_or_array_layers: 1 },
        );
        self.queue.submit([enc.finish()]);
        let slice = self.readback.slice(..);
        slice.map_async(wgpu::MapMode::Read, |_| {});
        self.device
            .poll(wgpu::PollType::wait_indefinitely())
            .map_err(|e| Error(e.to_string()))?;
        {
            let data = slice.get_mapped_range().map_err(|e| Error(e.to_string()))?;
            let tight = (self.width * 4) as usize;
            for (y, chunk) in data.chunks(row as usize).take(self.height as usize).enumerate() {
                self.pixels[y * tight..(y + 1) * tight].copy_from_slice(&chunk[..tight]);
            }
        }
        self.readback.unmap();
        Ok(&self.pixels)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const GRADIENT: &str = "fn main_image(p: vec2<f32>) -> vec4<f32> {
        return vec4<f32>(p.x / u.resolution.x, 0.0, fract(u.time), 1.0);
    }";

    const TOY: &str = "void mainImage(out vec4 c, in vec2 p) {
        c = vec4(p.x / iResolution.x, 0.0, fract(iTime), 1.0);
    }";

    #[test]
    fn bad_shaders_report_where_they_fail() {
        let e = compile("fn main_image(p: vec2<f32>) -> vec4<f32> { return nope; }", Lang::Wgsl)
            .unwrap_err();
        assert!(e.0.contains("nope"), "{e}");
        assert!(compile("void mainImage(out vec4 c, in vec2 p) { c = 1; }", Lang::Glsl).is_err());
        assert!(compile(GRADIENT, Lang::Wgsl).is_ok());
        assert!(compile(TOY, Lang::Glsl).is_ok());
    }

    #[test]
    fn renders_wgsl_and_glsl_pixels() {
        for (src, lang) in [(GRADIENT, Lang::Wgsl), (TOY, Lang::Glsl)] {
            let mut r = Renderer::new(src, lang, Format::Rgba, 100, 10).unwrap();
            let px = r.render(0.5).unwrap().to_vec();
            assert_eq!(px.len(), 100 * 10 * 4);
            let at = |x: usize| &px[x * 4..x * 4 + 4];
            assert!(at(0)[0] < 10, "{:?}", at(0));
            assert!(at(99)[0] > 240, "{:?}", at(99));
            assert!((at(50)[2] as i32 - 128).abs() < 4, "{:?}", at(50));
            assert_eq!(at(50)[3], 255);
            r.resize(37, 5);
            assert_eq!(r.render(0.0).unwrap().len(), 37 * 5 * 4);
        }
    }
}
