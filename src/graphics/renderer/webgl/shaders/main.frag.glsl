#version 300 es

precision highp float;
precision highp int;

uniform highp sampler2D u_hslToRgb;

flat in ivec4 v_data0;
flat in ivec4 v_data1;
flat in ivec4 v_data2;

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
    int x_a = v_data0.x;
    int x_b = v_data0.y;
    int x_c = v_data0.z;
    int y_a = v_data0.w;
    int y_b = v_data1.x;
    int y_c = v_data1.y;
    int colour_a = v_data1.z;
    int colour_b = v_data1.w;
    int colour_c = v_data2.x;

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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_a >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_b >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_c >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_c >> 7);
                        return;
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

                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_a >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_a >> 7);
                        return;
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

                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_b >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_c >> 7);
                        return;
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

                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_b >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_c >> 7);
                        return;
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

                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_a >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_a >> 7);
                        return;
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

                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_b >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_b >> 7);
                        return;
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

                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_c >> 7);
                        return;
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
                        
                        fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_a >> 7);
                        return;
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

                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_c >> 7);
                    return;
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
                    
                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_a >> 7);
                    return;
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

                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_b >> 7);
                    return;
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
                    
                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_b >> 7);
                    return;
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

                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_a >> 7, colour_c >> 7);
                    return;
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
                    
                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_b >> 7, colour_c >> 7);
                    return;
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

                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_a >> 7);
                    return;
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
                    
                    fragColor.rgb = calc_scanline_colour(scanline_x_a, scanline_x_b, colour_c >> 7, colour_b >> 7);
                    return;
                }
            }
        }
    }
    
    discard;
    // fragColor = vec4(1.0, 1.0, 1.0, 1.0);
}
