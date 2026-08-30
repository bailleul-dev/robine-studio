const std = @import("std");
const ui_assets = @import("ui_assets");
const lighting_lab = @import("robine").ui.lighting_lab;
const pedalboard_3d = @import("robine").ui.pedalboard_3d;

const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
    @cInclude("png.h");
});

const shadow_size = 1024;

pub const Frame = struct {
    vertices: []const lighting_lab.Vertex,
    lights: []const pedalboard_3d.EmissiveLight = &.{},
    camera: pedalboard_3d.CameraPose,
    key_position: [3]f32,
    key_size: [2]f32,
    key_intensity: f32,
    exposure: f32,
    environment_strength: f32,
    fill_radiance: [3]f32 = .{ 0, 0, 0 },
    light_field_of_view_degrees: f32 = 84,
    light_far: f32 = 30,
};

pub const Renderer = struct {
    program: c.GLuint,
    shadow_framebuffer: c.GLuint,
    shadow_texture: c.GLuint,
    surface_texture: c.GLuint,

    pub fn init() !Renderer {
        const program = try createProgram();
        errdefer c.glDeleteProgram(program);

        var shadow_texture: c.GLuint = 0;
        c.glGenTextures(1, &shadow_texture);
        errdefer c.glDeleteTextures(1, &shadow_texture);
        c.glBindTexture(c.GL_TEXTURE_2D, shadow_texture);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_DEPTH_COMPONENT24,
            shadow_size,
            shadow_size,
            0,
            c.GL_DEPTH_COMPONENT,
            c.GL_FLOAT,
            null,
        );
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_COMPARE_MODE, c.GL_COMPARE_R_TO_TEXTURE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_COMPARE_FUNC, c.GL_LEQUAL);

        var shadow_framebuffer: c.GLuint = 0;
        c.glGenFramebuffers(1, &shadow_framebuffer);
        errdefer c.glDeleteFramebuffers(1, &shadow_framebuffer);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, shadow_framebuffer);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, c.GL_TEXTURE_2D, shadow_texture, 0);
        c.glDrawBuffer(c.GL_NONE);
        c.glReadBuffer(c.GL_NONE);
        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE)
            return error.OpenGLShadowFramebufferIncomplete;
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

        const surface_texture = try createSurfaceTexture();
        errdefer c.glDeleteTextures(1, &surface_texture);

        c.glUseProgram(program);
        c.glUniform1i(c.glGetUniformLocation(program, "shadow_map"), 0);
        c.glUniform1i(c.glGetUniformLocation(program, "surface_texture"), 1);
        c.glUseProgram(0);

        return .{
            .program = program,
            .shadow_framebuffer = shadow_framebuffer,
            .shadow_texture = shadow_texture,
            .surface_texture = surface_texture,
        };
    }

    pub fn deinit(self: *Renderer) void {
        c.glDeleteTextures(1, &self.surface_texture);
        c.glDeleteFramebuffers(1, &self.shadow_framebuffer);
        c.glDeleteTextures(1, &self.shadow_texture);
        c.glDeleteProgram(self.program);
    }

    pub fn draw(self: *const Renderer, frame: Frame, width: u32, height: u32) void {
        self.drawShadow(frame);

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
        c.glViewport(0, 0, @intCast(width), @intCast(height));
        setCamera(frame.camera, @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)), 0.1, 40.0);
        c.glEnable(c.GL_DEPTH_TEST);
        c.glDisable(c.GL_LIGHTING);
        c.glUseProgram(self.program);

        const light_camera = pedalboard_3d.CameraPose{
            .camera = frame.key_position,
            .target = frame.camera.target,
            .field_of_view_degrees = frame.light_field_of_view_degrees,
        };
        const light_view_projection = viewProjection(light_camera, 1.0, 0.2, frame.light_far);
        uniformMatrix(self.program, "light_view_projection", light_view_projection);
        uniform3(self.program, "camera_position", frame.camera.camera);
        uniform3(self.program, "key_position", frame.key_position);
        c.glUniform2f(c.glGetUniformLocation(self.program, "key_size"), frame.key_size[0], frame.key_size[1]);
        c.glUniform1f(c.glGetUniformLocation(self.program, "key_intensity"), frame.key_intensity);
        c.glUniform1f(c.glGetUniformLocation(self.program, "exposure"), frame.exposure);
        c.glUniform1f(c.glGetUniformLocation(self.program, "environment_strength"), frame.environment_strength);
        uniform3(self.program, "fill_radiance", frame.fill_radiance);
        setEmissiveLights(self.program, frame.lights);

        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.shadow_texture);
        c.glActiveTexture(c.GL_TEXTURE1);
        c.glBindTexture(c.GL_TEXTURE_2D, self.surface_texture);
        drawTriangles(frame.vertices, true);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glUseProgram(0);
    }

    fn drawShadow(self: *const Renderer, frame: Frame) void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.shadow_framebuffer);
        c.glViewport(0, 0, shadow_size, shadow_size);
        c.glColorMask(c.GL_FALSE, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE);
        c.glClear(c.GL_DEPTH_BUFFER_BIT);
        c.glEnable(c.GL_DEPTH_TEST);
        c.glEnable(c.GL_POLYGON_OFFSET_FILL);
        c.glPolygonOffset(1.4, 3.0);
        c.glUseProgram(0);
        setCamera(.{
            .camera = frame.key_position,
            .target = frame.camera.target,
            .field_of_view_degrees = frame.light_field_of_view_degrees,
        }, 1.0, 0.2, frame.light_far);
        drawTriangles(frame.vertices, false);
        c.glDisable(c.GL_POLYGON_OFFSET_FILL);
        c.glColorMask(c.GL_TRUE, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE);
    }
};

const vertex_shader_source =
    \\#version 120
    \\uniform mat4 light_view_projection;
    \\varying vec3 world_position;
    \\varying vec3 world_normal;
    \\varying vec3 base_color;
    \\varying vec4 material;
    \\varying vec4 shadow_position;
    \\void main() {
    \\    world_position = gl_Vertex.xyz;
    \\    world_normal = normalize(gl_Normal.xyz);
    \\    base_color = gl_Color.rgb;
    \\    material = gl_MultiTexCoord0;
    \\    shadow_position = light_view_projection * gl_Vertex;
    \\    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
    \\}
;

const fragment_shader_source =
    \\#version 120
    \\uniform sampler2DShadow shadow_map;
    \\uniform sampler2D surface_texture;
    \\uniform vec3 camera_position;
    \\uniform vec3 key_position;
    \\uniform vec2 key_size;
    \\uniform float key_intensity;
    \\uniform float exposure;
    \\uniform float environment_strength;
    \\uniform vec3 fill_radiance;
    \\uniform vec4 emissive_position_radius[16];
    \\uniform vec4 emissive_color_intensity[16];
    \\uniform vec4 emissive_direction_cone[16];
    \\uniform int emissive_light_count;
    \\varying vec3 world_position;
    \\varying vec3 world_normal;
    \\varying vec3 base_color;
    \\varying vec4 material;
    \\varying vec4 shadow_position;
    \\
    \\const float PI = 3.14159265359;
    \\
    \\float distribution_ggx(vec3 n, vec3 h, float roughness) {
    \\    float a = roughness * roughness;
    \\    float a2 = a * a;
    \\    float ndoth = max(dot(n, h), 0.0);
    \\    float denominator = ndoth * ndoth * (a2 - 1.0) + 1.0;
    \\    return a2 / max(PI * denominator * denominator, 0.0001);
    \\}
    \\
    \\float geometry_schlick_ggx(float ndotv, float roughness) {
    \\    float r = roughness + 1.0;
    \\    float k = r * r * 0.125;
    \\    return ndotv / max(ndotv * (1.0 - k) + k, 0.0001);
    \\}
    \\
    \\float geometry_smith(vec3 n, vec3 v, vec3 l, float roughness) {
    \\    return geometry_schlick_ggx(max(dot(n, v), 0.0), roughness) *
    \\        geometry_schlick_ggx(max(dot(n, l), 0.0), roughness);
    \\}
    \\
    \\vec3 fresnel_schlick(float cosine, vec3 f0) {
    \\    return f0 + (1.0 - f0) * pow(clamp(1.0 - cosine, 0.0, 1.0), 5.0);
    \\}
    \\
    \\float shadow_visibility(vec4 position) {
    \\    vec3 projected = position.xyz / max(position.w, 0.0001);
    \\    vec2 uv = projected.xy * 0.5 + 0.5;
    \\    float depth = projected.z * 0.5 + 0.5;
    \\    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0 || depth <= 0.0 || depth >= 1.0)
    \\        return 1.0;
    \\    float visibility = 0.0;
    \\    vec2 texel = vec2(2.2 / 1024.0);
    \\    for (int y = -1; y <= 1; ++y) {
    \\        for (int x = -1; x <= 1; ++x) {
    \\            visibility += shadow2D(shadow_map, vec3(uv + vec2(float(x), float(y)) * texel, depth - 0.003)).r;
    \\        }
    \\    }
    \\    return visibility / 9.0;
    \\}
    \\
    \\vec3 aces_tonemap(vec3 color) {
    \\    const float a = 2.51;
    \\    const float b = 0.03;
    \\    const float cc = 2.43;
    \\    const float d = 0.59;
    \\    const float e = 0.14;
    \\    return clamp((color * (a * color + b)) / (color * (cc * color + d) + e), 0.0, 1.0);
    \\}
    \\
    \\void main() {
    \\    vec3 n = normalize(world_normal);
    \\    vec3 v = normalize(camera_position - world_position);
    \\    float roughness = clamp(material.x, 0.045, 1.0);
    \\    float metallic = clamp(material.y, 0.0, 1.0);
    \\    float emissive_strength = max(material.z, 0.0);
    \\    vec3 albedo = base_color;
    \\    if (material.w > 0.5) {
    \\        vec2 rug_uv = vec2((world_position.x + 19.90) / 6.80, 1.0 - (world_position.z + 3.55) / 7.40);
    \\        vec3 texture_color = texture2D(surface_texture, rug_uv).rgb;
    \\        float texture_luma = dot(texture_color, vec3(0.299, 0.587, 0.114));
    \\        vec3 stylized_neutral = vec3(texture_luma) * vec3(1.05, 0.94, 0.82);
    \\        albedo *= mix(stylized_neutral, texture_color, 0.78);
    \\    }
    \\    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    \\    vec3 direct = vec3(0.0);
    \\    float visibility = shadow_visibility(shadow_position);
    \\
    \\    const int sample_count = 9;
    \\    for (int sample_index = 0; sample_index < sample_count; ++sample_index) {
    \\        float t = float(sample_index) / float(sample_count - 1) - 0.5;
    \\        vec3 sample_position = key_position + vec3(0.0, 1.0, 0.0) * t * key_size.y;
    \\        vec3 difference = sample_position - world_position;
    \\        float distance_squared = max(dot(difference, difference), 0.2);
    \\        vec3 l = normalize(difference);
    \\        vec3 h = normalize(v + l);
    \\        float ndotl = max(dot(n, l), 0.0);
    \\        float ndotv = max(dot(n, v), 0.0);
    \\        float distribution = distribution_ggx(n, h, roughness);
    \\        float geometry = geometry_smith(n, v, l, roughness);
    \\        vec3 fresnel = fresnel_schlick(max(dot(h, v), 0.0), f0);
    \\        vec3 specular = distribution * geometry * fresnel / max(4.0 * ndotv * ndotl, 0.001);
    \\        vec3 diffuse = (1.0 - fresnel) * (1.0 - metallic) * albedo / PI;
    \\        float edge = 1.0 - abs(t) * 1.35;
    \\        vec3 radiance = vec3(1.0, 0.78, 0.54) * max(edge, 0.15) * key_intensity /
    \\            (distance_squared * float(sample_count));
    \\        direct += (diffuse + specular) * radiance * ndotl;
    \\    }
    \\
    \\    vec3 fill_l = normalize(vec3(0.78, 0.52, -0.36));
    \\    vec3 fill_h = normalize(v + fill_l);
    \\    float fill_ndotl = max(dot(n, fill_l), 0.0);
    \\    float fill_ndotv = max(dot(n, v), 0.0);
    \\    float fill_distribution = distribution_ggx(n, fill_h, roughness);
    \\    float fill_geometry = geometry_smith(n, v, fill_l, roughness);
    \\    vec3 fill_fresnel = fresnel_schlick(max(dot(fill_h, v), 0.0), f0);
    \\    vec3 fill_specular = fill_distribution * fill_geometry * fill_fresnel /
    \\        max(4.0 * fill_ndotv * fill_ndotl, 0.001);
    \\    vec3 fill_diffuse = (1.0 - fill_fresnel) * (1.0 - metallic) * albedo / PI;
    \\    direct += (fill_diffuse + fill_specular) * fill_radiance * fill_ndotl;
    \\
    \\    vec3 indicator_light = vec3(0.0);
    \\    for (int light_index = 0; light_index < 16; ++light_index) {
    \\        if (light_index >= emissive_light_count) break;
    \\        vec3 difference = emissive_position_radius[light_index].xyz - world_position;
    \\        float radius = emissive_position_radius[light_index].w;
    \\        float distance_squared = max(dot(difference, difference), 0.006);
    \\        float distance_to_light = sqrt(distance_squared);
    \\        vec3 led_l = difference / max(distance_to_light, 0.001);
    \\        float falloff = clamp(1.0 - distance_to_light / max(radius, 0.001), 0.0, 1.0);
    \\        falloff = falloff * falloff / max(distance_squared, 0.045);
    \\        float cone_cosine = emissive_direction_cone[light_index].w;
    \\        if (cone_cosine > -0.5) {
    \\            vec3 cone_direction = normalize(emissive_direction_cone[light_index].xyz);
    \\            float cone_alignment = dot(-led_l, cone_direction);
    \\            falloff *= smoothstep(cone_cosine, min(cone_cosine + 0.18, 0.98), cone_alignment);
    \\        }
    \\        float led_ndotl = max(dot(n, led_l), 0.0);
    \\        vec3 led_h = normalize(v + led_l);
    \\        vec3 led_fresnel = fresnel_schlick(max(dot(led_h, v), 0.0), f0);
    \\        float led_distribution = distribution_ggx(n, led_h, roughness);
    \\        float led_geometry = geometry_smith(n, v, led_l, roughness);
    \\        vec3 led_specular = led_distribution * led_geometry * led_fresnel /
    \\            max(4.0 * max(dot(n, v), 0.0) * led_ndotl, 0.001);
    \\        vec3 led_diffuse = (1.0 - led_fresnel) * (1.0 - metallic) * albedo / PI;
    \\        float local_scale = cone_cosine > -0.5 ? 0.42 : 0.055;
    \\        vec3 led_radiance = emissive_color_intensity[light_index].rgb *
    \\            emissive_color_intensity[light_index].w * falloff * local_scale;
    \\        indicator_light += (led_diffuse + led_specular) * led_radiance * led_ndotl;
    \\    }
    \\
    \\    vec3 reflection = reflect(-v, n);
    \\    float horizon = clamp(reflection.y * 0.5 + 0.5, 0.0, 1.0);
    \\    vec3 environment = mix(vec3(0.010, 0.007, 0.004), vec3(0.14, 0.095, 0.055), horizon);
    \\    vec3 to_strip = normalize(key_position - world_position);
    \\    float key_reflection_roughness = clamp(roughness + key_size.x * 0.035, 0.0, 1.0);
    \\    float strip_reflection = pow(max(dot(reflection, to_strip), 0.0), mix(150.0, 8.0, key_reflection_roughness));
    \\    environment += vec3(1.0, 0.72, 0.46) * strip_reflection * 3.2;
    \\    vec3 fixed_strip_direction = normalize(vec3(0.22, 0.91, -0.35));
    \\    float fixed_strip_roughness = clamp(roughness + 0.20, 0.0, 1.0);
    \\    float fixed_strip = pow(max(dot(reflection, fixed_strip_direction), 0.0), mix(110.0, 7.0, fixed_strip_roughness));
    \\    environment += vec3(0.42, 0.32, 0.22) * fixed_strip * 1.35;
    \\    vec3 ambient_fresnel = fresnel_schlick(max(dot(n, v), 0.0), f0);
    \\    vec3 ambient = environment * (ambient_fresnel + albedo * (1.0 - metallic) * 0.22) * environment_strength;
    \\    float clearcoat_strength = pow(1.0 - roughness, 3.0);
    \\    float clearcoat_fresnel = fresnel_schlick(max(dot(n, v), 0.0), vec3(0.04)).r;
    \\    ambient += vec3(0.52, 0.78, 0.96) * fixed_strip * clearcoat_strength * (0.55 + clearcoat_fresnel * 3.0);
    \\    float polished_visibility = metallic * pow(1.0 - roughness, 6.0);
    \\    float polished_warm = pow(max(dot(reflection, normalize(vec3(-0.48, 0.82, 0.31))), 0.0), 16.0);
    \\    float polished_cool = pow(max(dot(reflection, normalize(vec3(0.24, 0.91, -0.34))), 0.0), 12.0);
    \\    ambient += (vec3(1.0, 0.72, 0.46) * polished_warm + vec3(0.70, 0.52, 0.34) * polished_cool) *
    \\        polished_visibility * 0.62;
    \\    vec3 emitted = albedo * emissive_strength;
    \\    vec3 color = ambient + direct * mix(0.42, 1.0, visibility) + indicator_light + emitted;
    \\    color = aces_tonemap(color * exposure);
    \\    color = pow(color, vec3(1.0 / 2.2));
    \\    gl_FragColor = vec4(color, 1.0);
    \\}
;

fn createProgram() !c.GLuint {
    const vertex_shader = try compileShader(c.GL_VERTEX_SHADER, vertex_shader_source);
    defer c.glDeleteShader(vertex_shader);
    const fragment_shader = try compileShader(c.GL_FRAGMENT_SHADER, fragment_shader_source);
    defer c.glDeleteShader(fragment_shader);
    const program = c.glCreateProgram();
    if (program == 0) return error.OpenGLProgramCreationFailed;
    errdefer c.glDeleteProgram(program);
    c.glAttachShader(program, vertex_shader);
    c.glAttachShader(program, fragment_shader);
    c.glLinkProgram(program);
    var linked: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &linked);
    if (linked == 0) {
        logProgramError(program);
        return error.OpenGLProgramLinkFailed;
    }
    return program;
}

fn compileShader(kind: c.GLenum, source: []const u8) !c.GLuint {
    const shader = c.glCreateShader(kind);
    if (shader == 0) return error.OpenGLShaderCreationFailed;
    errdefer c.glDeleteShader(shader);
    const source_pointer: [*c]const c.GLchar = @ptrCast(source.ptr);
    const source_length: c.GLint = @intCast(source.len);
    c.glShaderSource(shader, 1, &source_pointer, &source_length);
    c.glCompileShader(shader);
    var compiled: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &compiled);
    if (compiled == 0) {
        logShaderError(shader);
        return error.OpenGLShaderCompilationFailed;
    }
    return shader;
}

fn logShaderError(shader: c.GLuint) void {
    var message: [4096]u8 = undefined;
    var length: c.GLsizei = 0;
    c.glGetShaderInfoLog(shader, message.len, &length, @ptrCast(&message));
    std.log.err("OpenGL shader compilation failed: {s}", .{message[0..@intCast(@max(length, 0))]});
}

fn logProgramError(program: c.GLuint) void {
    var message: [4096]u8 = undefined;
    var length: c.GLsizei = 0;
    c.glGetProgramInfoLog(program, message.len, &length, @ptrCast(&message));
    std.log.err("OpenGL shader link failed: {s}", .{message[0..@intCast(@max(length, 0))]});
}

fn createSurfaceTexture() !c.GLuint {
    var image: c.png_image = std.mem.zeroes(c.png_image);
    image.version = c.PNG_IMAGE_VERSION;
    if (c.png_image_begin_read_from_memory(
        &image,
        @ptrCast(ui_assets.persian_rug_stylized_v1.ptr),
        ui_assets.persian_rug_stylized_v1.len,
    ) == 0) return error.PngHeaderReadFailed;
    defer c.png_image_free(&image);
    image.format = c.PNG_FORMAT_RGBA;
    const pixel_count: usize = @as(usize, image.width) * @as(usize, image.height) * 4;
    const pixels = try std.heap.page_allocator.alloc(u8, pixel_count);
    defer std.heap.page_allocator.free(pixels);
    if (c.png_image_finish_read(&image, null, pixels.ptr, 0, null) == 0)
        return error.PngDecodeFailed;

    var texture: c.GLuint = 0;
    c.glGenTextures(1, &texture);
    if (texture == 0) return error.OpenGLTextureCreationFailed;
    c.glBindTexture(c.GL_TEXTURE_2D, texture);
    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_SRGB8_ALPHA8,
        @intCast(image.width),
        @intCast(image.height),
        0,
        c.GL_RGBA,
        c.GL_UNSIGNED_BYTE,
        pixels.ptr,
    );
    c.glGenerateMipmap(c.GL_TEXTURE_2D);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
    return texture;
}

fn setEmissiveLights(program: c.GLuint, lights: []const pedalboard_3d.EmissiveLight) void {
    var positions = [_][4]f32{.{ 0, 0, 0, 0 }} ** pedalboard_3d.Mesh.max_emissive_lights;
    var colors = [_][4]f32{.{ 0, 0, 0, 0 }} ** pedalboard_3d.Mesh.max_emissive_lights;
    var directions = [_][4]f32{.{ 0, 0, 0, -1 }} ** pedalboard_3d.Mesh.max_emissive_lights;
    const count = @min(lights.len, pedalboard_3d.Mesh.max_emissive_lights);
    for (lights[0..count], 0..) |light, index| {
        positions[index] = .{ light.position[0], light.position[1], light.position[2], light.radius };
        colors[index] = .{ light.color[0], light.color[1], light.color[2], light.intensity };
        directions[index] = .{ light.direction[0], light.direction[1], light.direction[2], light.cone_cosine };
    }
    c.glUniform4fv(c.glGetUniformLocation(program, "emissive_position_radius"), @intCast(positions.len), @ptrCast(&positions));
    c.glUniform4fv(c.glGetUniformLocation(program, "emissive_color_intensity"), @intCast(colors.len), @ptrCast(&colors));
    c.glUniform4fv(c.glGetUniformLocation(program, "emissive_direction_cone"), @intCast(directions.len), @ptrCast(&directions));
    c.glUniform1i(c.glGetUniformLocation(program, "emissive_light_count"), @intCast(count));
}

fn drawTriangles(vertices: []const lighting_lab.Vertex, include_material: bool) void {
    c.glBegin(c.GL_TRIANGLES);
    for (vertices) |vertex| {
        if (include_material) {
            c.glColor4fv(&vertex.base_color);
            c.glNormal3fv(&vertex.normal);
            c.glMultiTexCoord4fv(c.GL_TEXTURE0, &vertex.material);
        }
        c.glVertex4fv(&vertex.position);
    }
    c.glEnd();
}

fn uniformMatrix(program: c.GLuint, name: [*:0]const u8, matrix: [16]f32) void {
    c.glUniformMatrix4fv(c.glGetUniformLocation(program, name), 1, c.GL_FALSE, &matrix);
}

fn uniform3(program: c.GLuint, name: [*:0]const u8, value: [3]f32) void {
    c.glUniform3f(c.glGetUniformLocation(program, name), value[0], value[1], value[2]);
}

fn setCamera(camera: pedalboard_3d.CameraPose, aspect: f32, near: f32, far: f32) void {
    const projection = perspective(camera.field_of_view_degrees * std.math.pi / 180.0, aspect, near, far);
    const view = lookAt(camera.camera, camera.target, .{ 0, 1, 0 });
    c.glMatrixMode(c.GL_PROJECTION);
    c.glLoadMatrixf(&projection);
    c.glMatrixMode(c.GL_MODELVIEW);
    c.glLoadMatrixf(&view);
}

fn viewProjection(camera: pedalboard_3d.CameraPose, aspect: f32, near: f32, far: f32) [16]f32 {
    return multiplyMatrices(
        perspective(camera.field_of_view_degrees * std.math.pi / 180.0, aspect, near, far),
        lookAt(camera.camera, camera.target, .{ 0, 1, 0 }),
    );
}

fn perspective(field_of_view: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const scale = 1.0 / @tan(field_of_view * 0.5);
    var result = [_]f32{0} ** 16;
    result[0] = scale / aspect;
    result[5] = scale;
    result[10] = (far + near) / (near - far);
    result[11] = -1;
    result[14] = 2.0 * far * near / (near - far);
    return result;
}

fn lookAt(eye: [3]f32, target: [3]f32, up: [3]f32) [16]f32 {
    const z = normalized(.{ eye[0] - target[0], eye[1] - target[1], eye[2] - target[2] });
    const x = normalized(cross(up, z));
    const y = cross(z, x);
    return .{
        x[0],         y[0],         z[0],         0,
        x[1],         y[1],         z[1],         0,
        x[2],         y[2],         z[2],         0,
        -dot(x, eye), -dot(y, eye), -dot(z, eye), 1,
    };
}

fn multiplyMatrices(a: [16]f32, b: [16]f32) [16]f32 {
    var result: [16]f32 = undefined;
    for (0..4) |column| {
        for (0..4) |row| {
            var value: f32 = 0;
            for (0..4) |index| value += a[index * 4 + row] * b[column * 4 + index];
            result[column * 4 + row] = value;
        }
    }
    return result;
}

fn normalized(value: [3]f32) [3]f32 {
    const length = @sqrt(dot(value, value));
    return .{ value[0] / length, value[1] / length, value[2] / length };
}

fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
