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
        } else {
            strides = 0;
            shade_strides = 0;
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
        cur_u = u / cur_w;
        cur_v = v / cur_w;
        if (cur_u < 0) {
            cur_u = 0;
        } else if (cur_u > 0x3f80) {
            cur_u = 0x3f80;
        }
    }

    u = u + u_stride;
    v = v + v_stride;
    w = w + w_stride;

    cur_w = w >> 14;
    if (cur_w != 0) {
        next_u = u / cur_w;
        next_v = v / cur_w;
        if (next_u < 0x7) {
            next_u = 0x7;
        } else if (next_u > 0x3f80) {
            next_u = 0x3f80;
        }
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
            next_u = u / cur_w;
            next_v = v / cur_w;
            if (next_u < 0x7) {
                next_u = 0x7;
            } else if (next_u > 0x3f80) {
                next_u = 0x3f80;
            }
        }

        step_u = next_u - cur_u >> 3;
        step_v = next_v - cur_v >> 3;
        shade_a += shade_strides;
        cur_u += shade_a & 0x600000;
        shade_shift = shade_a >> 23;
    }

    cur_u += step_u * (scanline_x & 0x7);
    cur_v += step_v * (scanline_x & 0x7);

    int rgb = get_texel((cur_v & 0x3F80) + (cur_u >> 7), texture_id) >> shade_shift;

    if (rgb == 0) {
        return 0xff0000;
    }

    return rgb;
}

void main() {
    int x_a = v_data0.x;
    int x_b = v_data0.y;
    int x_c = v_data0.z;
    int y_a = v_data0.w;
    int y_b = v_data1.x;
    int y_c = v_data1.y;
    int colour_a = v_data1.z;
    int colour_b = v_data1.w;
    int colour_c = v_data2.x;
    int origin_x = v_data2.y;
    int origin_y = v_data2.z;
    int origin_z = v_data2.w;
    int tx_b = v_data3.x;
    int tx_c = v_data3.y;
    int ty_b = v_data3.z;
    int ty_c = v_data3.w;
    int tz_b = v_data4.x;
    int tz_c = v_data4.y;
    int texture_id = v_data4.z;

    int min_scanline_y = max(min(y_a, min(y_b, y_c)), 0);
    int max_scanline_y = max(y_a, max(y_b, y_c));
    int scanline_y = height - int(gl_FragCoord.y) - 1 - min_scanline_y;
    if (scanline_y < 0 || scanline_y >= max_scanline_y - min_scanline_y) {
        discard;
    }

    fragColor.a = 1.0;

    clip_x = x_a < 0
            || x_b < 0
            || x_c < 0
            || x_a > safe_width
            || x_b > safe_width
            || x_c > safe_width;
    
    int vertical_x = origin_x - tx_b;
    int vertical_y = origin_y - ty_b;
    int vertical_z = origin_z - tz_b;

    int horizontal_x = tx_c - origin_x;
    int horizontal_y = ty_c - origin_y;
    int horizontal_z = tz_c - origin_z;

    int u = ((horizontal_x * origin_y) - (horizontal_y * origin_x)) << 14;
    int u_stride = ((horizontal_y * origin_z) - (horizontal_z * origin_y)) << 8;
    int u_step_vertical = ((horizontal_z * origin_x) - (horizontal_x * origin_z)) << 5;

    int v = ((vertical_x * origin_y) - (vertical_y * origin_x)) << 14;
    int v_stride = ((vertical_y * origin_z) - (vertical_z * origin_y)) << 8;
    int v_step_vertical = ((vertical_z * origin_x) - (vertical_x * origin_z)) << 5;

    int w = ((vertical_y * horizontal_x) - (vertical_x * horizontal_y)) << 14;
    int w_stride = ((vertical_z * horizontal_y) - (vertical_y * horizontal_z)) << 8;
    int w_step_vertical = ((vertical_x * horizontal_z) - (vertical_z * horizontal_x)) << 5;

	int x_step_ab = 0;
	int colour_step_ab = 0;
	if (y_b != y_a) {
		x_step_ab = ((x_b - x_a) << 16) / (y_b - y_a);
        colour_step_ab = ((colour_b - colour_a) << 15) / (y_b - y_a);
	}

	int x_step_bc = 0;
	int colour_step_bc = 0;
	if (y_c != y_b) {
        x_step_bc = ((x_c - x_b) << 16) / (y_c - y_b);
        colour_step_bc = ((colour_c - colour_b) << 15) / (y_c - y_b);
	}

	int x_step_ac = 0;
	int colour_step_ac = 0;
	if (y_c != y_a) {
        x_step_ac = ((x_a - x_c) << 16) / (y_a - y_c);
        colour_step_ac = ((colour_a - colour_c) << 15) / (y_a - y_c);
	}

	if (y_a <= y_b && y_a <= y_c) {
        if (y_a < boundBottom) {
            if (y_b > boundBottom) {
                y_b = boundBottom;
            }

            if (y_c > boundBottom) {
                y_c = boundBottom;
            }

            if (y_b < y_c) {
                x_c = x_a <<= 16;
                colour_c = colour_a <<= 15;
                if (y_a < 0) {
                    x_c -= x_step_ac * y_a;
                    x_a -= x_step_ab * y_a;
                    colour_c -= colour_step_ac * y_a;
                    colour_a -= colour_step_ab * y_a;
                    y_a = 0;
                }

                x_b <<= 16;
                colour_b <<= 15;
                if (y_b < 0) {
                    x_b -= x_step_bc * y_b;
                    colour_b -= colour_step_bc * y_b;
                    y_b = 0;
                }

                int dy = y_a - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

                if (y_a != y_b && x_step_ac < x_step_ab || y_a == y_b && x_step_ac > x_step_bc) {
                    y_c -= y_b;
                    y_b -= y_a;
                    // yA = lineOffset[yA];

                    if (scanline_y < y_b) {
                        int delta_y = scanline_y;
                        x_c += x_step_ac * delta_y;
                        x_a += x_step_ab * delta_y;
                        int scanline_x_a = x_a >> 16;
                        int scanline_x_b = x_c >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_a >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_b < y_c) {
                        x_c += x_step_ac * y_b;
                        x_a += x_step_ab * y_b;
                        colour_c += colour_step_ac * y_b;
                        colour_a += colour_step_ab * y_b;

                        int delta_y = scanline_y - y_b;
                        x_c += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;
                        int scanline_x_a = x_c >> 16;
                        int scanline_x_b = x_b >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_b >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
                } else {
                    y_c -= y_b;
                    y_b -= y_a;
                    // yA = lineOffset[yA];

                    if (scanline_y < y_b) {
                        int delta_y = scanline_y;
                        x_c += x_step_ac * delta_y;
                        x_a += x_step_ab * delta_y;
                        int scanline_x_a = x_a >> 16;
                        int scanline_x_b = x_c >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_c >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_b < y_c) {
                        x_c += x_step_ac * y_b;
                        x_a += x_step_ab * y_b;
                        colour_c += colour_step_ac * y_b;
                        colour_a += colour_step_ab * y_b;

                        int delta_y = scanline_y - y_b;
                        x_c += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;
                        int scanline_x_a = x_b >> 16;
                        int scanline_x_b = x_c >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_c >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
                }
            } else {
                x_b = x_a <<= 16;
                colour_b = colour_a <<= 15;
                if (y_a < 0) {
                    x_b -= x_step_ac * y_a;
                    x_a -= x_step_ab * y_a;
                    colour_b -= colour_step_ac * y_a;
                    colour_a -= colour_step_ab * y_a;
                    y_a = 0;
                }

                x_c <<= 16;
                colour_c <<= 15;
                if (y_c < 0) {
                    x_c -= x_step_bc * y_c;
                    colour_c -= colour_step_bc * y_c;
                    y_c = 0;
                }

                int dy = y_a - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

                if (y_a != y_c && x_step_ac < x_step_ab || y_a == y_c && x_step_bc > x_step_ab) {
                    y_b -= y_c;
                    y_c -= y_a;
                    // yA = lineOffset[yA];

                    if (scanline_y < y_c) {
                        int delta_y = scanline_y;
                        x_b += x_step_ac * delta_y;
                        x_a += x_step_ab * delta_y;
                        
                        int scanline_x_a = x_b >> 16;
                        int scanline_x_b = x_a >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_b += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;

                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_a >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_c < y_b) {
                        x_b += x_step_ac * y_c;
                        x_a += x_step_ab * y_c;
                        colour_b += colour_step_ac * y_c;
                        colour_a += colour_step_ab * y_c;

                        int delta_y = scanline_y - y_c;
                        x_c += x_step_bc * delta_y;
                        x_a += x_step_ab * delta_y;
                        int scanline_x_a = x_c >> 16;
                        int scanline_x_b = x_a >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_bc * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_a >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
                } else {
                    y_b -= y_c;
                    y_c -= y_a;
                    // yA = lineOffset[yA];

                    if (scanline_y < y_c) {
                        int delta_y = scanline_y;
                        x_b += x_step_ac * delta_y;
                        x_a += x_step_ab * delta_y;
                        
                        int scanline_x_a = x_a >> 16;
                        int scanline_x_b = x_b >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_b += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;

                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_b >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_c < y_b) {
                        x_b += x_step_ac * y_c;
                        x_a += x_step_ab * y_c;
                        colour_b += colour_step_ac * y_c;
                        colour_a += colour_step_ab * y_c;

                        int delta_y = scanline_y - y_c;
                        x_c += x_step_bc * delta_y;
                        x_a += x_step_ab * delta_y;
                        int scanline_x_a = x_a >> 16;
                        int scanline_x_b = x_c >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_bc * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_c >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
                }
            }
        }
	} else if (y_b <= y_c) {
		if (y_b < boundBottom) {
			if (y_c > boundBottom) {
				y_c = boundBottom;
			}

			if (y_a > boundBottom) {
				y_a = boundBottom;
			}

			if (y_c < y_a) {
				x_a = x_b <<= 16;
				colour_a = colour_b <<= 15;
				if (y_b < 0) {
					x_a -= x_step_ab * y_b;
					x_b -= x_step_bc * y_b;
					colour_a -= colour_step_ab * y_b;
					colour_b -= colour_step_bc * y_b;
					y_b = 0;
				}

				x_c <<= 16;
				colour_c <<= 15;
				if (y_c < 0) {
					x_c -= x_step_ac * y_c;
					colour_c -= colour_step_ac * y_c;
					y_c = 0;
				}
                
                int dy = y_b - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

				if (y_b != y_c && x_step_ab < x_step_bc || y_b == y_c && x_step_ab > x_step_ac) {
					y_a -= y_c;
					y_c -= y_b;
					// yB = lineOffset[yB];
                    
                    if (scanline_y < y_c) {
                        int delta_y = scanline_y;
                        x_a += x_step_ab * delta_y;
                        x_b += x_step_bc * delta_y;
                        
                        int scanline_x_a = x_a >> 16;
                        int scanline_x_b = x_b >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;

                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_b >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_c < y_a) {
                        x_a += x_step_ab * y_c;
                        x_b += x_step_bc * y_c;
                        colour_a += colour_step_ab * y_c;
                        colour_b += colour_step_bc * y_c;

                        int delta_y = scanline_y - y_c;
                        x_a += x_step_ab * delta_y;
                        x_c += x_step_ac * delta_y;

                        int scanline_x_a = x_a >> 16;
                        int scanline_x_b = x_c >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_c += colour_step_ac * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_c >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
				} else {
					y_a -= y_c;
					y_c -= y_b;
					// yB = lineOffset[yB];

                    if (scanline_y < y_c) {
                        int delta_y = scanline_y;
                        x_a += x_step_ab * delta_y;
                        x_b += x_step_bc * delta_y;
                        
                        int scanline_x_a = x_b >> 16;
                        int scanline_x_b = x_a >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;

                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_a >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_c < y_a) {
                        x_a += x_step_ab * y_c;
                        x_b += x_step_bc * y_c;
                        colour_a += colour_step_ab * y_c;
                        colour_b += colour_step_bc * y_c;

                        int delta_y = scanline_y - y_c;
                        x_a += x_step_ab * delta_y;
                        x_c += x_step_ac * delta_y;

                        int scanline_x_a = x_c >> 16;
                        int scanline_x_b = x_a >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_c += colour_step_ac * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_a >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
				}
			} else {
				x_c = x_b <<= 16;
				colour_c = colour_b <<= 15;
				if (y_b < 0) {
					x_c -= x_step_ab * y_b;
					x_b -= x_step_bc * y_b;
					colour_c -= colour_step_ab * y_b;
					colour_b -= colour_step_bc * y_b;
					y_b = 0;
				}

				x_a <<= 16;
				colour_a <<= 15;
				if (y_a < 0) {
					x_a -= x_step_ac * y_a;
					colour_a -= colour_step_ac * y_a;
					y_a = 0;
				}
                
                int dy = y_b - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

				if (x_step_ab < x_step_bc) {
					y_c -= y_a;
					y_a -= y_b;
					// yB = lineOffset[yB];

                    if (scanline_y < y_a) {
                        int delta_y = scanline_y;
                        x_c += x_step_ab * delta_y;
                        x_b += x_step_bc * delta_y;
                        
                        int scanline_x_a = x_c >> 16;
                        int scanline_x_b = x_b >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;

                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_b >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_a < y_c) {
                        x_c += x_step_ab * y_a;
                        x_b += x_step_bc * y_a;
                        colour_c += colour_step_ab * y_a;
                        colour_b += colour_step_bc * y_a;

                        int delta_y = scanline_y - y_a;
                        x_a += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;

                        int scanline_x_a = x_a >> 16;
                        int scanline_x_b = x_b >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_a += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_b >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
				} else {
					y_c -= y_a;
					y_a -= y_b;
					// yB = lineOffset[yB];
                    
                    if (scanline_y < y_a) {
                        int delta_y = scanline_y;
                        x_c += x_step_ab * delta_y;
                        x_b += x_step_bc * delta_y;
                        
                        int scanline_x_a = x_b >> 16;
                        int scanline_x_b = x_c >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_c += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * delta_y;
                        v += v_step_vertical * delta_y;
                        w += w_step_vertical * delta_y;

                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_c >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    } else if (scanline_y - y_a < y_c) {
                        x_c += x_step_ab * y_a;
                        x_b += x_step_bc * y_a;
                        colour_c += colour_step_ab * y_a;
                        colour_b += colour_step_bc * y_a;

                        int delta_y = scanline_y - y_a;
                        x_a += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;

                        int scanline_x_a = x_b >> 16;
                        int scanline_x_b = x_a >> 16;
                        if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                            discard;
                        }
                        colour_a += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        u += u_step_vertical * scanline_y;
                        v += v_step_vertical * scanline_y;
                        w += w_step_vertical * scanline_y;
                        
                        int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_a >> 7);
                        if (rgb != 0) {
                            fragColor.rgb = unpack_colour888(rgb);
                            return;
                        }
                    }
				}
			}
		}
    } else if (y_c < boundBottom) {
     	if (y_a > boundBottom) {
			y_a = boundBottom;
		}

		if (y_b > boundBottom) {
			y_b = boundBottom;
		}

		if (y_a < y_b) {
			x_b = x_c <<= 16;
			colour_b = colour_c <<= 15;
			if (y_c < 0) {
				x_b -= x_step_bc * y_c;
				x_c -= x_step_ac * y_c;
				colour_b -= colour_step_bc * y_c;
				colour_c -= colour_step_ac * y_c;
				y_c = 0;
			}

			x_a <<= 16;
			colour_a <<= 15;
			if (y_a < 0) {
				x_a -= x_step_ab * y_a;
				colour_a -= colour_step_ab * y_a;
				y_a = 0;
			}
                
            int dy = y_c - centerY;
            u += u_step_vertical * dy;
            v += v_step_vertical * dy;
            w += w_step_vertical * dy;

            if (x_step_bc < x_step_ac) {
				y_b -= y_a;
				y_a -= y_c;
				// yC = lineOffset[yC];

                if (scanline_y < y_a) {
                    int delta_y = scanline_y;
                    x_b += x_step_bc * delta_y;
                    x_c += x_step_ac * delta_y;
                    
                    int scanline_x_a = x_b >> 16;
                    int scanline_x_b = x_c >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    u += u_step_vertical * delta_y;
                    v += v_step_vertical * delta_y;
                    w += w_step_vertical * delta_y;

                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_c >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                } else if (scanline_y - y_a < y_b) {
                    x_b += x_step_bc * y_a;
                    x_c += x_step_ac * y_a;
                    colour_b += colour_step_bc * y_a;
                    colour_c += colour_step_ac * y_a;

                    int delta_y = scanline_y - y_a;
                    x_b += x_step_bc * delta_y;
                    x_a += x_step_ab * delta_y;

                    int scanline_x_a = x_b >> 16;
                    int scanline_x_b = x_a >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_a += colour_step_ab * delta_y;

                    u += u_step_vertical * scanline_y;
                    v += v_step_vertical * scanline_y;
                    w += w_step_vertical * scanline_y;
                    
                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_a >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                }
			} else {
				y_b -= y_a;
				y_a -= y_c;
				// yC = lineOffset[yC];

                if (scanline_y < y_a) {
                    int delta_y = scanline_y;
                    x_b += x_step_bc * delta_y;
                    x_c += x_step_ac * delta_y;
                    
                    int scanline_x_a = x_c >> 16;
                    int scanline_x_b = x_b >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    u += u_step_vertical * delta_y;
                    v += v_step_vertical * delta_y;
                    w += w_step_vertical * delta_y;

                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_b >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                } else if (scanline_y - y_a < y_b) {
                    x_b += x_step_bc * y_a;
                    x_c += x_step_ac * y_a;
                    colour_b += colour_step_bc * y_a;
                    colour_c += colour_step_ac * y_a;

                    int delta_y = scanline_y - y_a;
                    x_b += x_step_bc * delta_y;
                    x_a += x_step_ab * delta_y;

                    int scanline_x_a = x_a >> 16;
                    int scanline_x_b = x_b >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_a += colour_step_ab * delta_y;

                    u += u_step_vertical * scanline_y;
                    v += v_step_vertical * scanline_y;
                    w += w_step_vertical * scanline_y;
                    
                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_b >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                }
			}
        } else {
			x_a = x_c <<= 16;
			colour_a = colour_c <<= 15;
			if (y_c < 0) {
				x_a -= x_step_bc * y_c;
				x_c -= x_step_ac * y_c;
				colour_a -= colour_step_bc * y_c;
				colour_c -= colour_step_ac * y_c;
				y_c = 0;
			}

			x_b <<= 16;
			colour_b <<= 15;
			if (y_b < 0) {
				x_b -= x_step_ab * y_b;
				colour_b -= colour_step_ab * y_b;
				y_b = 0;
			}
                
            int dy = y_c - centerY;
            u += u_step_vertical * dy;
            v += v_step_vertical * dy;
            w += w_step_vertical * dy;

			if (x_step_bc < x_step_ac) {
                y_a -= y_b;
                y_b -= y_c;
                
                if (scanline_y < y_b) {
                    int delta_y = scanline_y;
                    x_a += x_step_bc * delta_y;
                    x_c += x_step_ac * delta_y;
                    
                    int scanline_x_a = x_a >> 16;
                    int scanline_x_b = x_c >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_a += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    u += u_step_vertical * delta_y;
                    v += v_step_vertical * delta_y;
                    w += w_step_vertical * delta_y;

                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_a >> 7, colour_c >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                } else if (scanline_y - y_b < y_a) {
                    x_a += x_step_bc * y_b;
                    x_c += x_step_ac * y_b;
                    colour_a += colour_step_bc * y_b;
                    colour_c += colour_step_ac * y_b;

                    int delta_y = scanline_y - y_b;
                    x_b += x_step_ab * delta_y;
                    x_c += x_step_ac * delta_y;

                    int scanline_x_a = x_b >> 16;
                    int scanline_x_b = x_c >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_b += colour_step_ab * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    u += u_step_vertical * scanline_y;
                    v += v_step_vertical * scanline_y;
                    w += w_step_vertical * scanline_y;
                    
                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_b >> 7, colour_c >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                }
            } else {
				y_a -= y_b;
				y_b -= y_c;
				
                if (scanline_y < y_b) {
                    int delta_y = scanline_y;
                    x_a += x_step_bc * delta_y;
                    x_c += x_step_ac * delta_y;
                    
                    int scanline_x_a = x_c >> 16;
                    int scanline_x_b = x_a >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_a += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    u += u_step_vertical * delta_y;
                    v += v_step_vertical * delta_y;
                    w += w_step_vertical * delta_y;

                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_a >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                } else if (scanline_y - y_b < y_a) {
                    x_a += x_step_bc * y_b;
                    x_c += x_step_ac * y_b;
                    colour_a += colour_step_bc * y_b;
                    colour_c += colour_step_ac * y_b;

                    int delta_y = scanline_y - y_b;
                    x_b += x_step_ab * delta_y;
                    x_c += x_step_ac * delta_y;

                    int scanline_x_a = x_c >> 16;
                    int scanline_x_b = x_b >> 16;
                    if (is_outside_scanline(scanline_x_a, scanline_x_b)) {
                        discard;
                    }
                    colour_b += colour_step_ab * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    u += u_step_vertical * scanline_y;
                    v += v_step_vertical * scanline_y;
                    w += w_step_vertical * scanline_y;
                    
                    int rgb = calc_texel_colour(scanline_x_a, scanline_x_b, texture_id, 0, 0, u, v, w, u_stride, v_stride, w_stride, colour_c >> 7, colour_b >> 7);
                    if (rgb != 0) {
                        fragColor.rgb = unpack_colour888(rgb);
                        return;
                    }
                }
            }
        }
    }
    
    discard;
    // fragColor = vec4(1.0, 1.0, 1.0, 1.0);
}
