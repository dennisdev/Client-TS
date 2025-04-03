#version 300 es

precision highp float;
precision highp int;

uniform highp sampler2D u_hslToRgb;

flat in ivec4 v_data0;
flat in ivec4 v_data1;
flat in ivec4 v_data2;
flat in ivec4 v_data3;
flat in ivec4 v_data4;

out vec4 fragColor;

const int width = 512;
const int height = 334;

const int safe_width = width - 1;

const int boundBottom = height;

const int centerX = width / 2;

bool clip_x = false;

vec3 hsl_to_rgb(int hsl) {
    return texelFetch(u_hslToRgb, ivec2(hsl % 256, hsl / 256), 0).bgr;
}

int reciprocal15(int value) {
    return 32768 / value;
}

bool is_outside_scanline(int x_a, int x_b) {
    int frag_x = int(gl_FragCoord.x);
    return frag_x < x_a || frag_x >= x_b || x_a >= x_b || frag_x >= safe_width;
}

vec3 calc_scanline_colour(int x_a, int x_b, int colour_a, int colour_b) {
    int colour_step;
    int length;
    if (clip_x) {
        if (x_b - x_a > 3) {
            colour_step = (colour_b - colour_a) / (x_b - x_a);
        } else {
            colour_step = 0;
        }

        if (x_b > safe_width) {
            x_b = safe_width;
        }

        if (x_a < 0) {
            colour_a -= x_a * colour_step;
            x_a = 0;
        }

        length = (x_b - x_a) >> 2;
        colour_step <<= 2;
    } else if (x_a < x_b) {
        length = (x_b - x_a) >> 2;
        if (length > 0) {
            colour_step = (colour_b - colour_a) * reciprocal15(length) >> 15;
        }
    }
    int frag_x = int(gl_FragCoord.x);
    int scanline_x = frag_x - x_a;
    colour_a += colour_step * (scanline_x >> 2);
    return hsl_to_rgb(colour_a >> 8);
}

void main() {
    clip_x = (v_data0.x & 0x1) == 1;

    int min_scanline_y = v_data0.x >> 1;
    int max_scanline_y = v_data0.y;
    int scanline_y = height - int(gl_FragCoord.y) - 1 - min_scanline_y;
    if (scanline_y < 0 || scanline_y >= max_scanline_y - min_scanline_y) {
        discard;
    }

    fragColor.a = 1.0;

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

    if (scanline_y < line0_height) {
        int x_a = (line0_base_x_a + line0_step_x_a * scanline_y) >> 16;
        int x_b = (line0_base_x_b + line0_step_x_b * scanline_y) >> 16;
        if (is_outside_scanline(x_a, x_b)) {
            discard;
        }
        int colour_a = line0_base_colour_a + line0_step_colour_a * scanline_y;
        int colour_b = line0_base_colour_b + line0_step_colour_b * scanline_y;
        
        fragColor.rgb = calc_scanline_colour(x_a, x_b, colour_a >> 7, colour_b >> 7);
        return;
    } else if (scanline_y - line0_height < line1_height) {
        int delta_y = scanline_y - line0_height;

        int x_a = (line1_base_x_a + line1_step_x_a * delta_y) >> 16;
        int x_b = (line1_base_x_b + line1_step_x_b * delta_y) >> 16;
        if (is_outside_scanline(x_a, x_b)) {
            discard;
        }
        int colour_a = line1_base_colour_a + line1_step_colour_a * delta_y;
        int colour_b = line1_base_colour_b + line1_step_colour_b * delta_y;
        
        fragColor.rgb = calc_scanline_colour(x_a, x_b, colour_a >> 7, colour_b >> 7);
        return;
    }
    
    discard;
    // fragColor = vec4(1.0, 1.0, 1.0, 1.0);
}
