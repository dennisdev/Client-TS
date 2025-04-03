#version 300 es

precision highp float;
precision highp int;

uniform highp float u_triangleCount;

uniform highp usampler2D u_triangleData;

flat out ivec4 v_data0;
flat out ivec4 v_data1;
flat out ivec4 v_data2;
flat out ivec4 v_data3;
flat out ivec4 v_data4;

const int width = 512;
const int height = 334;

const int safe_width = width - 1;

const int boundBottom = height;

const vec2 dimensions = vec2(width, height);

const vec2 fullscreenVertices[3] = vec2[3](
    vec2(-1, -1), 
    vec2( 3, -1), 
    vec2(-1,  3)
);

uvec4 fetchData(int index) {
    return texelFetch(u_triangleData, ivec2(index % 4096, index / 4096), 0);
}

void main() {
    int triangleIndex = gl_VertexID / 3 * 2;

    uvec4 data0 = fetchData(triangleIndex);
    uvec4 data1 = fetchData(triangleIndex + 1);

    int x_a = int(data0.x >> uint(16)) - 32768;
    int x_b = int(data0.x & uint(0xffff)) - 32768;
    int x_c = int(data0.y >> uint(16)) - 32768;
    int y_a = int(data0.y & uint(0xffff)) - 32768;
    int y_b = int(data0.z >> uint(16)) - 32768;
    int y_c = int(data0.z & uint(0xffff)) - 32768;
    int colour_a = int(data0.w >> uint(16));
    int colour_b = int(data0.w & uint(0xffff));
    int colour_c = int(data1.x);

    float depth = 1.0 - float(data1.y) / u_triangleCount;

    int alpha = 255 - int(data1.z);

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

    int vertexIndex = gl_VertexID % 3;

    gl_Position = vec4(vertices[vertexIndex] * 2.0 / dimensions - 1.0, depth, 1.0);
    
    // flip y
    gl_Position.y *= -1.0;

    // gl_Position = vec4(fullscreenVertices[vertexIndex], depth, 1.0);

    int min_scanline_y = max(min_y, 0);

    bool clip_x = x_a < 0
            || x_b < 0
            || x_c < 0
            || x_a > safe_width
            || x_b > safe_width
            || x_c > safe_width;

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

                if (y_a != y_b && x_step_ac < x_step_ab || y_a == y_b && x_step_ac > x_step_bc) {
                    y_c -= y_b;
                    y_b -= y_a;

                    line0_height = y_b;
                    line0_base_x_a = x_c;
                    line0_base_x_b = x_a;
                    line0_step_x_a = x_step_ac;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = colour_c;
                    line0_base_colour_b = colour_a;
                    line0_step_colour_a = colour_step_ac;
                    line0_step_colour_b = colour_step_ab;

                    line1_height = y_c;
                    line1_base_x_a = x_c + x_step_ac * y_b;
                    line1_base_x_b = x_b;
                    line1_step_x_a = x_step_ac;
                    line1_step_x_b = x_step_bc;
                    line1_base_colour_a = colour_c + colour_step_ac * y_b;
                    line1_base_colour_b = colour_b;
                    line1_step_colour_a = colour_step_ac;
                    line1_step_colour_b = colour_step_bc;
                } else {
                    y_c -= y_b;
                    y_b -= y_a;

                    line0_height = y_b;
                    line0_base_x_a = x_a;
                    line0_base_x_b = x_c;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_ac;
                    line0_base_colour_a = colour_a;
                    line0_base_colour_b = colour_c;
                    line0_step_colour_a = colour_step_ab;
                    line0_step_colour_b = colour_step_ac;

                    line1_height = y_c;
                    line1_base_x_a = x_b;
                    line1_base_x_b = x_c + x_step_ac * y_b;
                    line1_step_x_a = x_step_bc;
                    line1_step_x_b = x_step_ac;
                    line1_base_colour_a = colour_b;
                    line1_base_colour_b = colour_c + colour_step_ac * y_b;
                    line1_step_colour_a = colour_step_bc;
                    line1_step_colour_b = colour_step_ac;
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

                if (y_a != y_c && x_step_ac < x_step_ab || y_a == y_c && x_step_bc > x_step_ab) {
                    y_b -= y_c;
                    y_c -= y_a;

                    line0_height = y_c;
                    line0_base_x_a = x_b;
                    line0_base_x_b = x_a;
                    line0_step_x_a = x_step_ac;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = colour_b;
                    line0_base_colour_b = colour_a;
                    line0_step_colour_a = colour_step_ac;
                    line0_step_colour_b = colour_step_ab;

                    line1_height = y_b;
                    line1_base_x_a = x_c;
                    line1_base_x_b = x_a + x_step_ab * y_c;
                    line1_step_x_a = x_step_bc;
                    line1_step_x_b = x_step_ab;
                    line1_base_colour_a = colour_c;
                    line1_base_colour_b = colour_a + colour_step_ab * y_c;
                    line1_step_colour_a = colour_step_bc;
                    line1_step_colour_b = colour_step_ab;
                } else {
                    y_b -= y_c;
                    y_c -= y_a;

                    line0_height = y_c;
                    line0_base_x_a = x_a;
                    line0_base_x_b = x_b;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_ac;
                    line0_base_colour_a = colour_a;
                    line0_base_colour_b = colour_b;
                    line0_step_colour_a = colour_step_ab;
                    line0_step_colour_b = colour_step_ac;

                    line1_height = y_b;
                    line1_base_x_a = x_a + x_step_ab * y_c;
                    line1_base_x_b = x_c;
                    line1_step_x_a = x_step_ab;
                    line1_step_x_b = x_step_bc;
                    line1_base_colour_a = colour_a + colour_step_ab * y_c;
                    line1_base_colour_b = colour_c;
                    line1_step_colour_a = colour_step_ab;
                    line1_step_colour_b = colour_step_bc;
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

				if (y_b != y_c && x_step_ab < x_step_bc || y_b == y_c && x_step_ab > x_step_ac) {
					y_a -= y_c;
					y_c -= y_b;

                    line0_height = y_c;
                    line0_base_x_a = x_a;
                    line0_base_x_b = x_b;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_bc;
                    line0_base_colour_a = colour_a;
                    line0_base_colour_b = colour_b;
                    line0_step_colour_a = colour_step_ab;
                    line0_step_colour_b = colour_step_bc;

                    line1_height = y_a;
                    line1_base_x_a = x_a + x_step_ab * y_c;
                    line1_base_x_b = x_c;
                    line1_step_x_a = x_step_ab;
                    line1_step_x_b = x_step_ac;
                    line1_base_colour_a = colour_a + colour_step_ab * y_c;
                    line1_base_colour_b = colour_c;
                    line1_step_colour_a = colour_step_ab;
                    line1_step_colour_b = colour_step_ac;
				} else {
					y_a -= y_c;
					y_c -= y_b;

                    line0_height = y_c;
                    line0_base_x_a = x_b;
                    line0_base_x_b = x_a;
                    line0_step_x_a = x_step_bc;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = colour_b;
                    line0_base_colour_b = colour_a;
                    line0_step_colour_a = colour_step_bc;
                    line0_step_colour_b = colour_step_ab;

                    line1_height = y_a;
                    line1_base_x_a = x_c;
                    line1_base_x_b = x_a + x_step_ab * y_c;
                    line1_step_x_a = x_step_ac;
                    line1_step_x_b = x_step_ab;
                    line1_base_colour_a = colour_c;
                    line1_base_colour_b = colour_a + colour_step_ab * y_c;
                    line1_step_colour_a = colour_step_ac;
                    line1_step_colour_b = colour_step_ab;
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

				if (x_step_ab < x_step_bc) {
					y_c -= y_a;
					y_a -= y_b;

                    line0_height = y_a;
                    line0_base_x_a = x_c;
                    line0_base_x_b = x_b;
                    line0_step_x_a = x_step_ab;
                    line0_step_x_b = x_step_bc;
                    line0_base_colour_a = colour_c;
                    line0_base_colour_b = colour_b;
                    line0_step_colour_a = colour_step_ab;
                    line0_step_colour_b = colour_step_bc;

                    line1_height = y_c;
                    line1_base_x_a = x_a;
                    line1_base_x_b = x_b + x_step_bc * y_a;
                    line1_step_x_a = x_step_ac;
                    line1_step_x_b = x_step_bc;
                    line1_base_colour_a = colour_a;
                    line1_base_colour_b = colour_b + colour_step_bc * y_a;
                    line1_step_colour_a = colour_step_ac;
                    line1_step_colour_b = colour_step_bc;
				} else {
					y_c -= y_a;
					y_a -= y_b;

                    line0_height = y_a;
                    line0_base_x_a = x_b;
                    line0_base_x_b = x_c;
                    line0_step_x_a = x_step_bc;
                    line0_step_x_b = x_step_ab;
                    line0_base_colour_a = colour_b;
                    line0_base_colour_b = colour_c;
                    line0_step_colour_a = colour_step_bc;
                    line0_step_colour_b = colour_step_ab;

                    line1_height = y_c;
                    line1_base_x_a = x_b + x_step_bc * y_a;
                    line1_base_x_b = x_a;
                    line1_step_x_a = x_step_bc;
                    line1_step_x_b = x_step_ac;
                    line1_base_colour_a = colour_b + colour_step_bc * y_a;
                    line1_base_colour_b = colour_a;
                    line1_step_colour_a = colour_step_bc;
                    line1_step_colour_b = colour_step_ac;
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

            if (x_step_bc < x_step_ac) {
				y_b -= y_a;
				y_a -= y_c;

                line0_height = y_a;
                line0_base_x_a = x_b;
                line0_base_x_b = x_c;
                line0_step_x_a = x_step_bc;
                line0_step_x_b = x_step_ac;
                line0_base_colour_a = colour_b;
                line0_base_colour_b = colour_c;
                line0_step_colour_a = colour_step_bc;
                line0_step_colour_b = colour_step_ac;

                line1_height = y_b;
                line1_base_x_a = x_b + x_step_bc * y_a;
                line1_base_x_b = x_a;
                line1_step_x_a = x_step_bc;
                line1_step_x_b = x_step_ab;
                line1_base_colour_a = colour_b + colour_step_bc * y_a;
                line1_base_colour_b = colour_a;
                line1_step_colour_a = colour_step_bc;
                line1_step_colour_b = colour_step_ab;
			} else {
				y_b -= y_a;
				y_a -= y_c;

                line0_height = y_a;
                line0_base_x_a = x_c;
                line0_base_x_b = x_b;
                line0_step_x_a = x_step_ac;
                line0_step_x_b = x_step_bc;
                line0_base_colour_a = colour_c;
                line0_base_colour_b = colour_b;
                line0_step_colour_a = colour_step_ac;
                line0_step_colour_b = colour_step_bc;

                line1_height = y_b;
                line1_base_x_a = x_a;
                line1_base_x_b = x_b + x_step_bc * y_a;
                line1_step_x_a = x_step_ab;
                line1_step_x_b = x_step_bc;
                line1_base_colour_a = colour_a;
                line1_base_colour_b = colour_b + colour_step_bc * y_a;
                line1_step_colour_a = colour_step_ab;
                line1_step_colour_b = colour_step_bc;
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

			if (x_step_bc < x_step_ac) {
                y_a -= y_b;
                y_b -= y_c;

                line0_height = y_b;
                line0_base_x_a = x_a;
                line0_base_x_b = x_c;
                line0_step_x_a = x_step_bc;
                line0_step_x_b = x_step_ac;
                line0_base_colour_a = colour_a;
                line0_base_colour_b = colour_c;
                line0_step_colour_a = colour_step_bc;
                line0_step_colour_b = colour_step_ac;

                line1_height = y_a;
                line1_base_x_a = x_b;
                line1_base_x_b = x_c + x_step_ac * y_b;
                line1_step_x_a = x_step_ab;
                line1_step_x_b = x_step_ac;
                line1_base_colour_a = colour_b;
                line1_base_colour_b = colour_c + colour_step_ac * y_b;
                line1_step_colour_a = colour_step_ab;
                line1_step_colour_b = colour_step_ac;
            } else {
				y_a -= y_b;
				y_b -= y_c;

                line0_height = y_b;
                line0_base_x_a = x_c;
                line0_base_x_b = x_a;
                line0_step_x_a = x_step_ac;
                line0_step_x_b = x_step_bc;
                line0_base_colour_a = colour_c;
                line0_base_colour_b = colour_a;
                line0_step_colour_a = colour_step_ac;
                line0_step_colour_b = colour_step_bc;

                line1_height = y_a;
                line1_base_x_a = x_c + x_step_ac * y_b;
                line1_base_x_b = x_b;
                line1_step_x_a = x_step_ac;
                line1_step_x_b = x_step_ab;
                line1_base_colour_a = colour_c + colour_step_ac * y_b;
                line1_base_colour_b = colour_b;
                line1_step_colour_a = colour_step_ac;
                line1_step_colour_b = colour_step_ab;
            }
        }
    }

    v_data0 = ivec4((min_scanline_y << 1) | (clip_x ? 1 : 0), (max_y << 8) | alpha, line0_height, line0_base_x_a);
    v_data1 = ivec4(line0_base_x_b, line0_step_x_a, line0_step_x_b, line0_base_colour_a);
    v_data2 = ivec4(line0_base_colour_b, line0_step_colour_a, line0_step_colour_b, line1_height);
    v_data3 = ivec4(line1_base_x_a, line1_base_x_b, line1_step_x_a, line1_step_x_b);
    v_data4 = ivec4(line1_base_colour_a, line1_base_colour_b, line1_step_colour_a, line1_step_colour_b);
}
