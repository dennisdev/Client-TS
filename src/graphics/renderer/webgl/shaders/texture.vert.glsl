#version 300 es

precision highp float;
precision highp int;

uniform bool u_textureTranslucent[50];

uniform highp float u_triangleCount;

uniform highp isampler2D u_triangleData;

flat out ivec4 v_data0;
flat out ivec4 v_data1;
flat out ivec4 v_data2;
flat out ivec4 v_data3;
flat out ivec4 v_data4;
flat out ivec4 v_data5;
flat out ivec4 v_data6;
flat out int v_data7;

const int width = 512;
const int height = 334;

const int safe_width = width - 1;

const int boundBottom = height;

const int centerX = width / 2;
const int centerY = height / 2;

const vec2 dimensions = vec2(width, height);

const vec2 fullscreenVertices[3] = vec2[3](
    vec2(-1, -1), 
    vec2( 3, -1), 
    vec2(-1,  3)
);

ivec4 fetchData(int index) {
    return texelFetch(u_triangleData, ivec2(index % 4096, index / 4096), 0);
}

void main() {
    int triangleIndex = gl_VertexID / 3 * 5;
    
    v_data0 = fetchData(triangleIndex);
    v_data1 = fetchData(triangleIndex + 1);
    v_data2 = fetchData(triangleIndex + 2);
    v_data3 = fetchData(triangleIndex + 3);
    v_data4 = fetchData(triangleIndex + 4);

    int x_a = v_data0.x;
    int x_b = v_data0.y;
    int x_c = v_data0.z;
    int y_a = v_data0.w;
    int y_b = v_data1.x;
    int y_c = v_data1.y;
    int shade_a = v_data1.z;
    int shade_b = v_data1.w;
    int shade_c = v_data2.x;
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

    // We have to create a larger triangle because the runescape rasterizer is different 
    // there will be missing pixels around the edges of the triangle if we don't
    // there might a better way to do this

    // Calculate the bounding box of the triangle
    int min_x = min(x_a, min(x_b, x_c));
    int max_x = max(x_a, max(x_b, x_c));
    int min_y = min(y_a, min(y_b, y_c));
    int max_y = max(y_a, max(y_b, y_c));

    // Calculate triangle that contains the bounding box
    vec2 vertices[3] = vec2[3](
        vec2(min_x, min_y),
        vec2(min_x, max_y + max_y - min_y),
        vec2(max_x + max_x - min_x, min_y)
    );

    float depth = 1.0 - float(v_data4.w) / u_triangleCount;

    int vertexIndex = gl_VertexID % 3;

    gl_Position = vec4(vertices[vertexIndex] * 2.0 / dimensions - 1.0, depth, 1.0);
    
    // flip y
    gl_Position.y *= -1.0;

    // gl_Position = vec4(fullscreenVertices[vertexIndex], depth, 1.0);

    bool opaque = !u_textureTranslucent[texture_id];

    int min_scanline_y = max(min_y, 0);

    bool clip_x = x_a < 0
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
    int shade_step_ab = 0;
    if (y_b != y_a) {
        x_step_ab = ((x_b - x_a) << 16) / (y_b - y_a);
        shade_step_ab = ((shade_b - shade_a) << 16) / (y_b - y_a);
    }

    int x_step_bc = 0;
    int shade_step_bc = 0;
    if (y_c != y_b) {
        x_step_bc = ((x_c - x_b) << 16) / (y_c - y_b);
        shade_step_bc = ((shade_c - shade_b) << 16) / (y_c - y_b);
    }

    int x_step_ac = 0;
    int shade_step_ac = 0;
    if (y_c != y_a) {
        x_step_ac = ((x_a - x_c) << 16) / (y_a - y_c);
        shade_step_ac = ((shade_a - shade_c) << 16) / (y_a - y_c);
    }

    int line0_height = 0;
    int line0_base_x_a = 0;
    int line0_base_x_b = 0;
    int line0_step_x_a = 0;
    int line0_step_x_b = 0;
    int line0_base_colour_a = 0;
    int line0_base_colour_b = 0;
    int line0_step_colour_a = 0;
    int line0_step_colour_b = 0;

    int line1_height = 0;
    int line1_base_x_a = 0;
    int line1_base_x_b = 0;
    int line1_step_x_a = 0;
    int line1_step_x_b = 0;
    int line1_base_colour_a = 0;
    int line1_base_colour_b = 0;
    int line1_step_colour_a = 0;
    int line1_step_colour_b = 0;

    if (y_a <= y_b && y_a <= y_c) {
        if (y_a < boundBottom) {
            if (y_b > boundBottom) {
                y_b = boundBottom;
            }

            if (y_c > boundBottom) {
                y_c = boundBottom;
            }

            if (y_b < y_c) {
                x_a <<= 16;
                x_c = x_a;
                shade_a <<= 16;
                shade_c = shade_a;
                if (y_a < 0) {
                    x_c -= x_step_ac * y_a;
                    x_a -= x_step_ab * y_a;
                    shade_c -= shade_step_ac * y_a;
                    shade_a -= shade_step_ab * y_a;
                    y_a = 0;
                }

                x_b <<= 16;
                shade_b <<= 16;
                if (y_b < 0) {
                    x_b -= x_step_bc * y_b;
                    shade_b -= shade_step_bc * y_b;
                    y_b = 0;
                }

                int dy = y_a - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

                if (y_a != y_b && x_step_ac < x_step_ab || y_a == y_b && x_step_ac > x_step_bc) {
                    y_c -= y_b;
                    y_b -= y_a;

                    line0_height = y_b;
                    line0_base_x_a = x_c;
                    line0_base_x_b = x_a;
                    line0_step_x_a = x_step_ac;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = shade_c;
                    line0_base_colour_b = shade_a;
                    line0_step_colour_a = shade_step_ac;
                    line0_step_colour_b = shade_step_ab;

                    line1_height = y_c;
                    line1_base_x_a = x_c + x_step_ac * y_b;
                    line1_base_x_b = x_b;
                    line1_step_x_a = x_step_ac;
                    line1_step_x_b = x_step_bc;
                    line1_base_colour_a = shade_c + shade_step_ac * y_b;
                    line1_base_colour_b = shade_b;
                    line1_step_colour_a = shade_step_ac;
                    line1_step_colour_b = shade_step_bc;
                } else {
                    y_c -= y_b;
                    y_b -= y_a;
                    
                    line0_height = y_b;
                    line0_base_x_a = x_a;
                    line0_base_x_b = x_c;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_ac;
                    line0_base_colour_a = shade_a;
                    line0_base_colour_b = shade_c;
                    line0_step_colour_a = shade_step_ab;
                    line0_step_colour_b = shade_step_ac;

                    line1_height = y_c;
                    line1_base_x_a = x_b;
                    line1_base_x_b = x_c + x_step_ac * y_b;
                    line1_step_x_a = x_step_bc;
                    line1_step_x_b = x_step_ac;
                    line1_base_colour_a = shade_b;
                    line1_base_colour_b = shade_c + shade_step_ac * y_b;
                    line1_step_colour_a = shade_step_bc;
                    line1_step_colour_b = shade_step_ac;
                }
            } else {
                x_a <<= 16;
                x_b = x_a;
                shade_a <<= 16;
                shade_b = shade_a;
                if (y_a < 0) {
                    x_b -= x_step_ac * y_a;
                    x_a -= x_step_ab * y_a;
                    shade_b -= shade_step_ac * y_a;
                    shade_a -= shade_step_ab * y_a;
                    y_a = 0;
                }

                x_c <<= 16;
                shade_c <<= 16;
                if (y_c < 0) {
                    x_c -= x_step_bc * y_c;
                    shade_c -= shade_step_bc * y_c;
                    y_c = 0;
                }

                int dy = y_a - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

                if (y_a != y_c && x_step_ac < x_step_ab || y_a == y_c && x_step_bc > x_step_ab) {
                    y_b -= y_c;
                    y_c -= y_a;

                    line0_height = y_c;
                    line0_base_x_a = x_b;
                    line0_base_x_b = x_a;
                    line0_step_x_a = x_step_ac;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = shade_b;
                    line0_base_colour_b = shade_a;
                    line0_step_colour_a = shade_step_ac;
                    line0_step_colour_b = shade_step_ab;

                    line1_height = y_b;
                    line1_base_x_a = x_c;
                    line1_base_x_b = x_a + x_step_ab * y_c;
                    line1_step_x_a = x_step_bc;
                    line1_step_x_b = x_step_ab;
                    line1_base_colour_a = shade_c;
                    line1_base_colour_b = shade_a + shade_step_ab * y_c;
                    line1_step_colour_a = shade_step_bc;
                    line1_step_colour_b = shade_step_ab;
                } else {
                    y_b -= y_c;
                    y_c -= y_a;

                    line0_height = y_c;
                    line0_base_x_a = x_a;
                    line0_base_x_b = x_b;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_ac;
                    line0_base_colour_a = shade_a;
                    line0_base_colour_b = shade_b;
                    line0_step_colour_a = shade_step_ab;
                    line0_step_colour_b = shade_step_ac;

                    line1_height = y_b;
                    line1_base_x_a = x_a + x_step_ab * y_c;
                    line1_base_x_b = x_c;
                    line1_step_x_a = x_step_ab;
                    line1_step_x_b = x_step_bc;
                    line1_base_colour_a = shade_a + shade_step_ab * y_c;
                    line1_base_colour_b = shade_c;
                    line1_step_colour_a = shade_step_ab;
                    line1_step_colour_b = shade_step_bc;
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
                x_b <<= 16;
                x_a = x_b;
                shade_b <<= 16;
                shade_a = shade_b;
                if (y_b < 0) {
                    x_a -= x_step_ab * y_b;
                    x_b -= x_step_bc * y_b;
                    shade_a -= shade_step_ab * y_b;
                    shade_b -= shade_step_bc * y_b;
                    y_b = 0;
                }

                x_c <<= 16;
                shade_c <<= 16;
                if (y_c < 0) {
                    x_c -= x_step_ac * y_c;
                    shade_c -= shade_step_ac * y_c;
                    y_c = 0;
                }

                int dy = y_b - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

				if (y_b != y_c && x_step_ab < x_step_bc || y_b == y_c && x_step_ab > x_step_ac) {
					y_a -= y_c;
					y_c -= y_b;

                    line0_height = y_c;
                    line0_base_x_a = x_a;
                    line0_base_x_b = x_b;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_bc;
                    line0_base_colour_a = shade_a;
                    line0_base_colour_b = shade_b;
                    line0_step_colour_a = shade_step_ab;
                    line0_step_colour_b = shade_step_bc;

                    line1_height = y_a;
                    line1_base_x_a = x_a + x_step_ab * y_c;
                    line1_base_x_b = x_c;
                    line1_step_x_a = x_step_ab;
                    line1_step_x_b = x_step_ac;
                    line1_base_colour_a = shade_a + shade_step_ab * y_c;
                    line1_base_colour_b = shade_c;
                    line1_step_colour_a = shade_step_ab;
                    line1_step_colour_b = shade_step_ac;
				} else {
					y_a -= y_c;
					y_c -= y_b;

                    line0_height = y_c;
                    line0_base_x_a = x_b;
                    line0_base_x_b = x_a;
                    line0_step_x_a = x_step_bc;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = shade_b;
                    line0_base_colour_b = shade_a;
                    line0_step_colour_a = shade_step_bc;
                    line0_step_colour_b = shade_step_ab;

                    line1_height = y_a;
                    line1_base_x_a = x_c;
                    line1_base_x_b = x_a + x_step_ab * y_c;
                    line1_step_x_a = x_step_ac;
                    line1_step_x_b = x_step_ab;
                    line1_base_colour_a = shade_c;
                    line1_base_colour_b = shade_a + shade_step_ab * y_c;
                    line1_step_colour_a = shade_step_ac;
                    line1_step_colour_b = shade_step_ab;
				}
            } else {
                x_b <<= 16;
                x_c = x_b;
                shade_b <<= 16;
                shade_c = shade_b;
                if (y_b < 0) {
                    x_c -= x_step_ab * y_b;
                    x_b -= x_step_bc * y_b;
                    shade_c -= shade_step_ab * y_b;
                    shade_b -= shade_step_bc * y_b;
                    y_b = 0;
                }

                x_a <<= 16;
                shade_a <<= 16;
                if (y_a < 0) {
                    x_a -= x_step_ac * y_a;
                    shade_a -= shade_step_ac * y_a;
                    y_a = 0;
                }

                int dy = y_b - centerY;
                u += u_step_vertical * dy;
                v += v_step_vertical * dy;
                w += w_step_vertical * dy;

				if (x_step_ab < x_step_bc) {
					y_c -= y_a;
					y_a -= y_b;

                    line0_height = y_a;
                    line0_base_x_a = x_c;
                    line0_base_x_b = x_b;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_bc;
                    line0_base_colour_a = shade_c;
                    line0_base_colour_b = shade_b;
                    line0_step_colour_a = shade_step_ab;
                    line0_step_colour_b = shade_step_bc;

                    line1_height = y_c;
                    line1_base_x_a = x_a;
                    line1_base_x_b = x_b + x_step_bc * y_a;
                    line1_step_x_a = x_step_ac;
                    line1_step_x_b = x_step_bc;
                    line1_base_colour_a = shade_a;
                    line1_base_colour_b = shade_b + shade_step_bc * y_a;
                    line1_step_colour_a = shade_step_ac;
                    line1_step_colour_b = shade_step_bc;
				} else {
					y_c -= y_a;
					y_a -= y_b;

                    line0_height = y_a;
                    line0_base_x_a = x_b;
                    line0_base_x_b = x_c;
                    line0_step_x_a = x_step_bc;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = shade_b;
                    line0_base_colour_b = shade_c;
                    line0_step_colour_a = shade_step_bc;
                    line0_step_colour_b = shade_step_ab;

                    line1_height = y_c;
                    line1_base_x_a = x_b + x_step_bc * y_a;
                    line1_base_x_b = x_a;
                    line1_step_x_a = x_step_bc;
                    line1_step_x_b = x_step_ac;
                    line1_base_colour_a = shade_b + shade_step_bc * y_a;
                    line1_base_colour_b = shade_a;
                    line1_step_colour_a = shade_step_bc;
                    line1_step_colour_b = shade_step_ac;
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
            x_c <<= 16;
            x_b = x_c;
            shade_c <<= 16;
            shade_b = shade_c;
            if (y_c < 0) {
                x_b -= x_step_bc * y_c;
                x_c -= x_step_ac * y_c;
                shade_b -= shade_step_bc * y_c;
                shade_c -= shade_step_ac * y_c;
                y_c = 0;
            }

            x_a <<= 16;
            shade_a <<= 16;
            if (y_a < 0) {
                x_a -= x_step_ab * y_a;
                shade_a -= shade_step_ab * y_a;
                y_a = 0;
            }

            int dy = y_c - centerY;
            u += u_step_vertical * dy;
            v += v_step_vertical * dy;
            w += w_step_vertical * dy;

            if (x_step_bc < x_step_ac) {
				y_b -= y_a;
				y_a -= y_c;

                line0_height = y_a;
                line0_base_x_a = x_b;
                line0_base_x_b = x_c;
                line0_step_x_a = x_step_bc;
                line0_step_x_b = x_step_ac;
                line0_base_colour_a = shade_b;
                line0_base_colour_b = shade_c;
                line0_step_colour_a = shade_step_bc;
                line0_step_colour_b = shade_step_ac;

                line1_height = y_b;
                line1_base_x_a = x_b + x_step_bc * y_a;
                line1_base_x_b = x_a;
                line1_step_x_a = x_step_bc;
                line1_step_x_b = x_step_ab;
                line1_base_colour_a = shade_b + shade_step_bc * y_a;
                line1_base_colour_b = shade_a;
                line1_step_colour_a = shade_step_bc;
                line1_step_colour_b = shade_step_ab;
			} else {
				y_b -= y_a;
				y_a -= y_c;

                line0_height = y_a;
                line0_base_x_a = x_c;
                line0_base_x_b = x_b;
                line0_step_x_a = x_step_ac;
                line0_step_x_b = x_step_bc;
                line0_base_colour_a = shade_c;
                line0_base_colour_b = shade_b;
                line0_step_colour_a = shade_step_ac;
                line0_step_colour_b = shade_step_bc;

                line1_height = y_b;
                line1_base_x_a = x_a;
                line1_base_x_b = x_b + x_step_bc * y_a;
                line1_step_x_a = x_step_ab;
                line1_step_x_b = x_step_bc;
                line1_base_colour_a = shade_a;
                line1_base_colour_b = shade_b + shade_step_bc * y_a;
                line1_step_colour_a = shade_step_ab;
                line1_step_colour_b = shade_step_bc;
			}
        } else {
            x_c <<= 16;
            x_a = x_c;
            shade_c <<= 16;
            shade_a = shade_c;
            if (y_c < 0) {
                x_a -= x_step_bc * y_c;
                x_c -= x_step_ac * y_c;
                shade_a -= shade_step_bc * y_c;
                shade_c -= shade_step_ac * y_c;
                y_c = 0;
            }

            x_b <<= 16;
            shade_b <<= 16;
            if (y_b < 0) {
                x_b -= x_step_ab * y_b;
                shade_b -= shade_step_ab * y_b;
                y_b = 0;
            }

            int dy = y_c - centerY;
            u += u_step_vertical * dy;
            v += v_step_vertical * dy;
            w += w_step_vertical * dy;

			if (x_step_bc < x_step_ac) {
                y_a -= y_b;
                y_b -= y_c;

                line0_height = y_b;
                line0_base_x_a = x_a;
                line0_base_x_b = x_c;
                line0_step_x_a = x_step_bc;
                line0_step_x_b = x_step_ac;
                line0_base_colour_a = shade_a;
                line0_base_colour_b = shade_c;
                line0_step_colour_a = shade_step_bc;
                line0_step_colour_b = shade_step_ac;

                line1_height = y_a;
                line1_base_x_a = x_b;
                line1_base_x_b = x_c + x_step_ac * y_b;
                line1_step_x_a = x_step_ab;
                line1_step_x_b = x_step_ac;
                line1_base_colour_a = shade_b;
                line1_base_colour_b = shade_c + shade_step_ac * y_b;
                line1_step_colour_a = shade_step_ab;
                line1_step_colour_b = shade_step_ac;
            } else {
				y_a -= y_b;
				y_b -= y_c;

                line0_height = y_b;
                line0_base_x_a = x_c;
                line0_base_x_b = x_a;
                line0_step_x_a = x_step_ac;
                line0_step_x_b = x_step_bc;
                line0_base_colour_a = shade_c;
                line0_base_colour_b = shade_a;
                line0_step_colour_a = shade_step_ac;
                line0_step_colour_b = shade_step_bc;

                line1_height = y_a;
                line1_base_x_a = x_c + x_step_ac * y_b;
                line1_base_x_b = x_b;
                line1_step_x_a = x_step_ac;
                line1_step_x_b = x_step_ab;
                line1_base_colour_a = shade_c + shade_step_ac * y_b;
                line1_base_colour_b = shade_b;
                line1_step_colour_a = shade_step_ac;
                line1_step_colour_b = shade_step_ab;
            }
        }
    }

    v_data0 = ivec4((min_scanline_y << 2) | (opaque ? 0x2 : 0) | (clip_x ? 1 : 0), (max_y << 8) | texture_id, line0_height, line0_base_x_a);
    v_data1 = ivec4(line0_base_x_b, line0_step_x_a, line0_step_x_b, line0_base_colour_a);
    v_data2 = ivec4(line0_base_colour_b, line0_step_colour_a, line0_step_colour_b, line1_height);
    v_data3 = ivec4(line1_base_x_a, line1_base_x_b, line1_step_x_a, line1_step_x_b);
    v_data4 = ivec4(line1_base_colour_a, line1_base_colour_b, line1_step_colour_a, line1_step_colour_b);
    v_data5 = ivec4(u, v, w, u_stride);
    v_data6 = ivec4(v_stride, w_stride, u_step_vertical, v_step_vertical);
    v_data7 = w_step_vertical;
}
