#version 300 es

precision highp float;
precision highp int;

uniform highp sampler2D u_hslToRgb;
uniform highp sampler2DArray u_textures;

flat in ivec4 v_data0;
flat in ivec4 v_data1;
flat in ivec4 v_data2;
flat in ivec4 v_data3;
flat in ivec4 v_data4;
flat in ivec4 v_data5;
flat in ivec4 v_data6;
flat in int v_data7;

out vec4 fragColor;

const int width = 512;
const int height = 334;

const int safe_width = width - 1;

const int boundBottom = height;

const int centerX = width / 2;
const int centerY = height / 2;

bool clip_x = false;

vec3 hsl_to_rgb(int hsl) {
    return texelFetch(u_hslToRgb, ivec2(hsl % 256, hsl / 256), 0).bgr;
}

vec3 unpack_colour888(int rgb) {
    float r = float((rgb >> 16) & 0xff) / 255.0;
    float g = float((rgb >> 8) & 0xff) / 255.0;
    float b = float(rgb & 0xff) / 255.0;
    return vec3(r, g, b);
}

int pack_colour888(vec3 rgb) {
    int r = int(rgb.r * 255.0);
    int g = int(rgb.g * 255.0);
    int b = int(rgb.b * 255.0);
    return (r << 16) | (g << 8) | b;
}

int get_texel(int index, int texture_id) {
    int x = index % 128;
    int y = index / 128;
    return pack_colour888(texelFetch(u_textures, ivec3(x, y, texture_id), 0).bgr);
}

int reciprocal15(int value) {
    return 32768 / value;
}

bool is_outside_scanline(int x_a, int x_b) {
    int frag_x = int(gl_FragCoord.x);
    return frag_x < x_a || frag_x >= x_b || x_a >= x_b || frag_x >= safe_width;
}

int calc_texel_colour(
    int x_a, 
    int x_b,
    int texture_id,
    int cur_u,
    int cur_v,
    int u,
    int v,
    int w,
    int u_stride,
    int v_stride,
    int w_stride,
    int shade_a, 
    int shade_b
) {
    int shade_strides = 0;
    int strides = 0;
    if (clip_x) {
        shade_strides = (shade_b - shade_a) / (x_b - x_a);

        if (x_b > safe_width) {
            x_b = safe_width;
        }

        if (x_a < 0) {
            shade_a -= x_a * shade_strides;
            x_a = 0;
        }

        strides = (x_b - x_a) >> 3;
        shade_strides <<= 12;
        shade_a <<= 9;
    } else {
        if (x_b - x_a > 7) {
            strides = (x_b - x_a) >> 3;
            shade_strides = (shade_b - shade_a) * reciprocal15(strides) >> 6;
        }

        shade_a <<= 9;
    }

    int next_u = 0;
    int next_v = 0;
    int dx = x_a - centerX;

    u = u + (u_stride >> 3) * dx;
    v = v + (v_stride >> 3) * dx;
    w = w + (w_stride >> 3) * dx;

    int cur_w = w >> 14;
    if (cur_w != 0) {
        cur_u = clamp(u / cur_w, 0, 0x3f80);
        cur_v = v / cur_w;
    }

    u = u + u_stride;
    v = v + v_stride;
    w = w + w_stride;

    cur_w = w >> 14;
    if (cur_w != 0) {
        next_u = clamp(u / cur_w, 0x7, 0x3f80);
        next_v = v / cur_w;
    }

    int step_u = next_u - cur_u >> 3;
    int step_v = next_v - cur_v >> 3;
    cur_u += shade_a & 0x600000;
    int shade_shift = shade_a >> 23;

    int frag_x = int(gl_FragCoord.x);
    int scanline_x = frag_x - x_a;

    strides = scanline_x >> 3;

    for (; strides > 0; strides--) {
        cur_u = next_u;
        cur_v = next_v;

        u += u_stride;
        v += v_stride;
        w += w_stride;

        cur_w = w >> 14;
        if (cur_w != 0) {
            next_u = clamp(u / cur_w, 0x7, 0x3f80);
            next_v = v / cur_w;
        }

        step_u = next_u - cur_u >> 3;
        step_v = next_v - cur_v >> 3;
        shade_a += shade_strides;
        cur_u += shade_a & 0x600000;
        shade_shift = shade_a >> 23;
    }

    cur_u += step_u * (scanline_x & 0x7);
    cur_v += step_v * (scanline_x & 0x7);

    return get_texel((cur_v & 0x3F80) + (cur_u >> 7), texture_id) >> shade_shift;
}

void main() {
    clip_x = (v_data0.x & 0x1) == 1;
    bool opaque = (v_data0.x & 0x2) == 2;

    int min_scanline_y = v_data0.x >> 2;
    int max_scanline_y = v_data0.y >> 8;
    int scanline_y = height - int(gl_FragCoord.y) - 1 - min_scanline_y;
    if (scanline_y < 0 || scanline_y >= max_scanline_y - min_scanline_y) {
        discard;
    }

    fragColor.a = 1.0;

    int texture_id = v_data0.y & 0xff;

    int line0_height = v_data0.z;
    int line0_base_x_a = v_data0.w;
    int line0_base_x_b = v_data1.x;
    int line0_step_x_a = v_data1.y;
    int line0_step_x_b = v_data1.z;
    int line0_base_colour_a = v_data1.w;
    int line0_base_colour_b = v_data2.x;
    int line0_step_colour_a = v_data2.y;
    int line0_step_colour_b = v_data2.z;

    int line1_height = v_data2.w;
    int line1_base_x_a = v_data3.x;
    int line1_base_x_b = v_data3.y;
    int line1_step_x_a = v_data3.z;
    int line1_step_x_b = v_data3.w;
    int line1_base_colour_a = v_data4.x;
    int line1_base_colour_b = v_data4.y;
    int line1_step_colour_a = v_data4.z;
    int line1_step_colour_b = v_data4.w;

    int u = v_data5.x;
    int v = v_data5.y;
    int w = v_data5.z;
    int u_stride = v_data5.w;
    int v_stride = v_data6.x;
    int w_stride = v_data6.y;
    int u_step_vertical = v_data6.z;
    int v_step_vertical = v_data6.w;
    int w_step_vertical = v_data7;

    if (scanline_y < line0_height) {
        int x_a = (line0_base_x_a + line0_step_x_a * scanline_y) >> 16;
        int x_b = (line0_base_x_b + line0_step_x_b * scanline_y) >> 16;
        if (is_outside_scanline(x_a, x_b)) {
            discard;
        }
        int colour_a = line0_base_colour_a + line0_step_colour_a * scanline_y;
        int colour_b = line0_base_colour_b + line0_step_colour_b * scanline_y;

        int rgb = calc_texel_colour(
            x_a, 
            x_b, 
            texture_id, 
            0, 
            0, 
            u + u_step_vertical * scanline_y, 
            v + v_step_vertical * scanline_y, 
            w + w_step_vertical * scanline_y, 
            u_stride, 
            v_stride, 
            w_stride, 
            colour_a >> 8, 
            colour_b >> 8
        );
        if (opaque || rgb != 0) {
            fragColor.rgb = unpack_colour888(rgb);
            return;
        }
    } else if (scanline_y - line0_height < line1_height) {
        int delta_y = scanline_y - line0_height;

        int x_a = (line1_base_x_a + line1_step_x_a * delta_y) >> 16;
        int x_b = (line1_base_x_b + line1_step_x_b * delta_y) >> 16;
        if (is_outside_scanline(x_a, x_b)) {
            discard;
        }
        int colour_a = line1_base_colour_a + line1_step_colour_a * delta_y;
        int colour_b = line1_base_colour_b + line1_step_colour_b * delta_y;
        
        int rgb = calc_texel_colour(
            x_a, 
            x_b, 
            texture_id, 
            0, 
            0, 
            u + u_step_vertical * scanline_y, 
            v + v_step_vertical * scanline_y, 
            w + w_step_vertical * scanline_y, 
            u_stride, 
            v_stride, 
            w_stride, 
            colour_a >> 8, 
            colour_b >> 8
        );
        if (opaque || rgb != 0) {
            fragColor.rgb = unpack_colour888(rgb);
            return;
        }
    }
    
    discard;
    // fragColor = vec4(1.0, 1.0, 1.0, 1.0);
}
