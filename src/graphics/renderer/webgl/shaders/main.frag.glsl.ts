import { hslToRgbFunction } from './commons.glsl';

export const SHADER_CODE: string = `
#version 300 es

precision highp float;
precision highp int;

uniform highp sampler2D u_hslToRgb;

flat in ivec3 xs;
flat in ivec3 ys;
flat in ivec3 colors;

out vec4 fragColor;

const int width = 512;
const int height = 334;

const int boundBottom = height;

const int centerX = width / 2;

vec3 hslToRgb(int hsl) {
    return texelFetch(u_hslToRgb, ivec2(hsl % 256, hsl / 256), 0).bgr;
}

int reciprocal15(int value) {
    return 32768 / value;
}

bool isOutsideScanline(int xA, int xB) {
    int fragX = int(gl_FragCoord.x);
    return fragX < xA || fragX >= xB || xA >= xB || fragX >= width - 1;
}

vec3 getScanlineColor(int xA, int xB, int colorA, int colorB) {
    int fragX = int(gl_FragCoord.x);
    if (fragX < xA || fragX >= xB) {
        // discard;
    }
    int colorStep;
    int length;
    if (xA < xB) {
        length = (xB - xA) >> 2;
        if (length > 0) {
            colorStep = (colorB - colorA) * reciprocal15(length) >> 15;
        }
    } else {
        // discard;
    }
    int scanlineX = fragX - xA;
    colorA += colorStep * (scanlineX >> 2);
    return hslToRgb(colorA >> 8);
}

void main() {
    int x_a = xs.x;
    int x_b = xs.y;
    int x_c = xs.z;
    int y_a = ys.x;
    int y_b = ys.y;
    int y_c = ys.z;
    int colour_a = colors.x;
    int colour_b = colors.y;
    int colour_c = colors.z;

    int minScanlineY = max(min(y_a, min(y_b, y_c)), 0);
    int maxScanlineY = max(y_a, max(y_b, y_c));
    int scanline_y = height - int(gl_FragCoord.y) - 1 - minScanlineY;
    if (scanline_y < 0 || scanline_y > maxScanlineY - minScanlineY) {
        discard;
    }

    fragColor.a = 1.0;

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

    int currentScanline = 0;

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
                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                        return;
                    } else if (scanline_y - y_b < y_c) {
                        x_c += x_step_ac * y_b;
                        x_a += x_step_ab * y_b;
                        colour_c += colour_step_ac * y_b;
                        colour_a += colour_step_ab * y_b;

                        int delta_y = scanline_y - y_b;
                        x_c += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;
                        int scanlineXA = x_c >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                        return;
                    }

                    // while (--y_b >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_a >> 16;
                    //         int scanlineXB = x_c >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yA, 0);
                    //     x_c += x_step_ac;
                    //     x_a += x_step_ab;
                    //     colour_c += colour_step_ac;
                    //     colour_a += colour_step_ab;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
                    // while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_c >> 16;
                    //         int scanlineXB = x_b >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yA, 0);
                    //     x_c += x_step_ac;
                    //     x_b += x_step_bc;
                    //     colour_c += colour_step_ac;
                    //     colour_b += colour_step_bc;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
                } else {
                    y_c -= y_b;
                    y_b -= y_a;
                    // yA = lineOffset[yA];

                    if (scanline_y < y_b) {
                        int delta_y = scanline_y;
                        x_c += x_step_ac * delta_y;
                        x_a += x_step_ab * delta_y;
                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                        return;
                    } else if (scanline_y - y_b < y_c) {
                        x_c += x_step_ac * y_b;
                        x_a += x_step_ab * y_b;
                        colour_c += colour_step_ac * y_b;
                        colour_a += colour_step_ab * y_b;

                        int delta_y = scanline_y - y_b;
                        x_c += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;
                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                        return;
                    }

                    // while (--y_b >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_a >> 16;
                    //         int scanlineXB = x_c >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yA, 0);
                    //     x_c += x_step_ac;
                    //     x_a += x_step_ab;
                    //     colour_c += colour_step_ac;
                    //     colour_a += colour_step_ab;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
                    // while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_b >> 16;
                    //         int scanlineXB = x_c >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yA, 0);
                    //     x_c += x_step_ac;
                    //     x_b += x_step_bc;
                    //     colour_c += colour_step_ac;
                    //     colour_b += colour_step_bc;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
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
                        
                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_a >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_b += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                        return;
                    } else if (scanline_y - y_c < y_b) {
                        x_b += x_step_ac * y_c;
                        x_a += x_step_ab * y_c;
                        colour_b += colour_step_ac * y_c;
                        colour_a += colour_step_ab * y_c;

                        int delta_y = scanline_y - y_c;
                        x_c += x_step_bc * delta_y;
                        x_a += x_step_ab * delta_y;
                        int scanlineXA = x_c >> 16;
                        int scanlineXB = x_a >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_bc * delta_y;
                        colour_a += colour_step_ab * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                        return;
                    }

                    // while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_b >> 16;
                    //         int scanlineXB = x_a >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yA, 0);
                    //     x_b += x_step_ac;
                    //     x_a += x_step_ab;
                    //     colour_b += colour_step_ac;
                    //     colour_a += colour_step_ab;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
                    // while (--y_b >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_c >> 16;
                    //         int scanlineXB = x_a >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yA, 0);
                    //     x_c += x_step_bc;
                    //     x_a += x_step_ab;
                    //     colour_c += colour_step_bc;
                    //     colour_a += colour_step_ab;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
                } else {
                    y_b -= y_c;
                    y_c -= y_a;
                    // yA = lineOffset[yA];

                    if (scanline_y < y_c) {
                        int delta_y = scanline_y;
                        x_b += x_step_ac * delta_y;
                        x_a += x_step_ab * delta_y;
                        
                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_b += colour_step_ac * delta_y;
                        colour_a += colour_step_ab * delta_y;

                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                        return;
                    } else if (scanline_y - y_c < y_b) {
                        x_b += x_step_ac * y_c;
                        x_a += x_step_ab * y_c;
                        colour_b += colour_step_ac * y_c;
                        colour_a += colour_step_ab * y_c;

                        int delta_y = scanline_y - y_c;
                        x_c += x_step_bc * delta_y;
                        x_a += x_step_ab * delta_y;
                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_bc * delta_y;
                        colour_a += colour_step_ab * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                        return;
                    }

                    // while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_a >> 16;
                    //         int scanlineXB = x_b >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yA, 0);
                    //     x_b += x_step_ac;
                    //     x_a += x_step_ab;
                    //     colour_b += colour_step_ac;
                    //     colour_a += colour_step_ab;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
                    // while (--y_b >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_a >> 16;
                    //         int scanlineXB = x_c >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                    //         return;
                    //     }
                    //     // gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yA, 0);
                    //     x_c += x_step_bc;
                    //     x_a += x_step_ab;
                    //     colour_c += colour_step_bc;
                    //     colour_a += colour_step_ab;
                    //     // yA += width2d;
                    //     currentScanline++;
                    // }
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
                        
                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                        return;
                    } else if (scanline_y - y_c < y_a) {
                        x_a += x_step_ab * y_c;
                        x_b += x_step_bc * y_c;
                        colour_a += colour_step_ab * y_c;
                        colour_b += colour_step_bc * y_c;

                        int delta_y = scanline_y - y_c;
                        x_a += x_step_ab * delta_y;
                        x_c += x_step_ac * delta_y;

                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_c += colour_step_ac * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                        return;
                    }

					// while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_a >> 16;
                    //         int scanlineXB = x_b >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yB, 0);
					// 	x_a += x_step_ab;
					// 	x_b += x_step_bc;
					// 	colour_a += colour_step_ab;
					// 	colour_b += colour_step_bc;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
					// while (--y_a >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_a >> 16;
                    //         int scanlineXB = x_c >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yB, 0);
					// 	x_a += x_step_ab;
					// 	x_c += x_step_ac;
					// 	colour_a += colour_step_ab;
					// 	colour_c += colour_step_ac;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
				} else {
					y_a -= y_c;
					y_c -= y_b;
					// yB = lineOffset[yB];

                    if (scanline_y < y_c) {
                        int delta_y = scanline_y;
                        x_a += x_step_ab * delta_y;
                        x_b += x_step_bc * delta_y;
                        
                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_a >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                        return;
                    } else if (scanline_y - y_c < y_a) {
                        x_a += x_step_ab * y_c;
                        x_b += x_step_bc * y_c;
                        colour_a += colour_step_ab * y_c;
                        colour_b += colour_step_bc * y_c;

                        int delta_y = scanline_y - y_c;
                        x_a += x_step_ab * delta_y;
                        x_c += x_step_ac * delta_y;

                        int scanlineXA = x_c >> 16;
                        int scanlineXB = x_a >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_a += colour_step_ab * delta_y;
                        colour_c += colour_step_ac * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                        return;
                    }

					// while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_b >> 16;
                    //         int scanlineXB = x_a >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yB, 0);
					// 	x_a += x_step_ab;
					// 	x_b += x_step_bc;
					// 	colour_a += colour_step_ab;
					// 	colour_b += colour_step_bc;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
					// while (--y_a >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_c >> 16;
                    //         int scanlineXB = x_a >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yB, 0);
					// 	x_a += x_step_ab;
					// 	x_c += x_step_ac;
					// 	colour_a += colour_step_ab;
					// 	colour_c += colour_step_ac;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
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
                        
                        int scanlineXA = x_c >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                        return;
                    } else if (scanline_y - y_a < y_c) {
                        x_c += x_step_ab * y_a;
                        x_b += x_step_bc * y_a;
                        colour_c += colour_step_ab * y_a;
                        colour_b += colour_step_bc * y_a;

                        int delta_y = scanline_y - y_a;
                        x_a += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;

                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_a += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                        return;
                    }

					// while (--y_a >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_c >> 16;
                    //         int scanlineXB = x_b >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yB, 0);
					// 	x_c += x_step_ab;
					// 	x_b += x_step_bc;
					// 	colour_c += colour_step_ab;
					// 	colour_b += colour_step_bc;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
					// while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_a >> 16;
                    //         int scanlineXB = x_b >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yB, 0);
					// 	x_a += x_step_ac;
					// 	x_b += x_step_bc;
					// 	colour_a += colour_step_ac;
					// 	colour_b += colour_step_bc;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
				} else {
					y_c -= y_a;
					y_a -= y_b;
					// yB = lineOffset[yB];
                    
                    if (scanline_y < y_a) {
                        int delta_y = scanline_y;
                        x_c += x_step_ab * delta_y;
                        x_b += x_step_bc * delta_y;
                        
                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_c += colour_step_ab * delta_y;
                        colour_b += colour_step_bc * delta_y;

                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                        return;
                    } else if (scanline_y - y_a < y_c) {
                        x_c += x_step_ab * y_a;
                        x_b += x_step_bc * y_a;
                        colour_c += colour_step_ab * y_a;
                        colour_b += colour_step_bc * y_a;

                        int delta_y = scanline_y - y_a;
                        x_a += x_step_ac * delta_y;
                        x_b += x_step_bc * delta_y;

                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_a >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        colour_a += colour_step_ac * delta_y;
                        colour_b += colour_step_bc * delta_y;
                        
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                        return;
                    }

					// while (--y_a >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_b >> 16;
                    //         int scanlineXB = x_c >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yB, 0);
					// 	x_c += x_step_ab;
					// 	x_b += x_step_bc;
					// 	colour_c += colour_step_ab;
					// 	colour_b += colour_step_bc;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
					// while (--y_c >= 0) {
                    //     if (currentScanline == scanline_y) {
                    //         int scanlineXA = x_b >> 16;
                    //         int scanlineXB = x_a >> 16;
                    //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                    //             discard;
                    //         }
                    //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                    //         return;
                    //     }
					// 	// gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yB, 0);
					// 	x_a += x_step_ac;
					// 	x_b += x_step_bc;
					// 	colour_a += colour_step_ac;
					// 	colour_b += colour_step_bc;
					// 	// yB += width2d;
                    //     currentScanline++;
					// }
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
                    
                    int scanlineXA = x_b >> 16;
                    int scanlineXB = x_c >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                    return;
                } else if (scanline_y - y_a < y_b) {
                    x_b += x_step_bc * y_a;
                    x_c += x_step_ac * y_a;
                    colour_b += colour_step_bc * y_a;
                    colour_c += colour_step_ac * y_a;

                    int delta_y = scanline_y - y_a;
                    x_b += x_step_bc * delta_y;
                    x_a += x_step_ab * delta_y;

                    int scanlineXA = x_b >> 16;
                    int scanlineXB = x_a >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_a += colour_step_ab * delta_y;
                    
                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                    return;
                }

				// while (--y_a >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_b >> 16;
                //         int scanlineXB = x_c >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                //         return;
                //     }
				// 	// gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yC, 0);
				// 	x_b += x_step_bc;
				// 	x_c += x_step_ac;
				// 	colour_b += colour_step_bc;
				// 	colour_c += colour_step_ac;
				// 	// yC += width2d;
                //     currentScanline++;
				// }
				// while (--y_b >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_b >> 16;
                //         int scanlineXB = x_a >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_a >> 7);
                //         return;
                //     }
				// 	// gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yC, 0);
				// 	x_b += x_step_bc;
				// 	x_a += x_step_ab;
				// 	colour_b += colour_step_bc;
				// 	colour_a += colour_step_ab;
				// 	// yC += width2d;
                //     currentScanline++;
				// }
			} else {
				y_b -= y_a;
				y_a -= y_c;
				// yC = lineOffset[yC];

                if (scanline_y < y_a) {
                    int delta_y = scanline_y;
                    x_b += x_step_bc * delta_y;
                    x_c += x_step_ac * delta_y;
                    
                    int scanlineXA = x_c >> 16;
                    int scanlineXB = x_b >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                    return;
                } else if (scanline_y - y_a < y_b) {
                    x_b += x_step_bc * y_a;
                    x_c += x_step_ac * y_a;
                    colour_b += colour_step_bc * y_a;
                    colour_c += colour_step_ac * y_a;

                    int delta_y = scanline_y - y_a;
                    x_b += x_step_bc * delta_y;
                    x_a += x_step_ab * delta_y;

                    int scanlineXA = x_a >> 16;
                    int scanlineXB = x_b >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_b += colour_step_bc * delta_y;
                    colour_a += colour_step_ab * delta_y;
                    
                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                    return;
                }

				// while (--y_a >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_c >> 16;
                //         int scanlineXB = x_b >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                //         return;
                //     }
				// 	// gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yC, 0);
				// 	x_b += x_step_bc;
				// 	x_c += x_step_ac;
				// 	colour_b += colour_step_bc;
				// 	colour_c += colour_step_ac;
				// 	// yC += width2d;
                //     currentScanline++;
				// }
				// while (--y_b >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_a >> 16;
                //         int scanlineXB = x_b >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_b >> 7);
                //         return;
                //     }
				// 	// gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yC, 0);
				// 	x_b += x_step_bc;
				// 	x_a += x_step_ab;
				// 	colour_b += colour_step_bc;
				// 	colour_a += colour_step_ab;
				// 	// yC += width2d;
                //     currentScanline++;
				// }
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
                    
                    int scanlineXA = x_a >> 16;
                    int scanlineXB = x_c >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_a += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                    return;
                } else if (scanline_y - y_b < y_a) {
                    x_a += x_step_bc * y_b;
                    x_c += x_step_ac * y_b;
                    colour_a += colour_step_bc * y_b;
                    colour_c += colour_step_ac * y_b;

                    int delta_y = scanline_y - y_b;
                    x_b += x_step_ab * delta_y;
                    x_c += x_step_ac * delta_y;

                    int scanlineXA = x_b >> 16;
                    int scanlineXB = x_c >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_b += colour_step_ab * delta_y;
                    colour_c += colour_step_ac * delta_y;
                    
                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                    return;
                }

                // while (--y_b >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_a >> 16;
                //         int scanlineXB = x_c >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_a >> 7, colour_c >> 7);
                //         return;
                //     }
                //     // gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yC, 0);
                //     x_a += x_step_bc;
                //     x_c += x_step_ac;
                //     colour_a += colour_step_bc;
                //     colour_c += colour_step_ac;
                //     // yC += width2d;
                //     currentScanline++;
                // }
                // while (--y_a >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_b >> 16;
                //         int scanlineXB = x_c >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_b >> 7, colour_c >> 7);
                //         return;
                //     }
                //     // gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yC, 0);
                //     x_b += x_step_ab;
                //     x_c += x_step_ac;
                //     colour_b += colour_step_ab;
                //     colour_c += colour_step_ac;
                //     // yC += width2d;
                //     currentScanline++;
                // }
            } else {
				y_a -= y_b;
				y_b -= y_c;
				
                if (scanline_y < y_b) {
                    int delta_y = scanline_y;
                    x_a += x_step_bc * delta_y;
                    x_c += x_step_ac * delta_y;
                    
                    int scanlineXA = x_c >> 16;
                    int scanlineXB = x_a >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_a += colour_step_bc * delta_y;
                    colour_c += colour_step_ac * delta_y;

                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                    return;
                } else if (scanline_y - y_b < y_a) {
                    x_a += x_step_bc * y_b;
                    x_c += x_step_ac * y_b;
                    colour_a += colour_step_bc * y_b;
                    colour_c += colour_step_ac * y_b;

                    int delta_y = scanline_y - y_b;
                    x_b += x_step_ab * delta_y;
                    x_c += x_step_ac * delta_y;

                    int scanlineXA = x_c >> 16;
                    int scanlineXB = x_b >> 16;
                    if (isOutsideScanline(scanlineXA, scanlineXB)) {
                        discard;
                    }
                    colour_b += colour_step_ab * delta_y;
                    colour_c += colour_step_ac * delta_y;
                    
                    fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                    return;
                }

                // while (--y_b >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_c >> 16;
                //         int scanlineXB = x_a >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_a >> 7);
                //         return;
                //     }
				// 	// gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yC, 0);
				// 	x_a += x_step_bc;
				// 	x_c += x_step_ac;
				// 	colour_a += colour_step_bc;
				// 	colour_c += colour_step_ac;
				// 	// yC += width2d;
                //     currentScanline++;
				// }
				// while (--y_a >= 0) {
                //     if (currentScanline == scanline_y) {
                //         int scanlineXA = x_c >> 16;
                //         int scanlineXB = x_b >> 16;
                //         if (isOutsideScanline(scanlineXA, scanlineXB)) {
                //             discard;
                //         }
                //         fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, colour_c >> 7, colour_b >> 7);
                //         return;
                //     }
				// 	// gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yC, 0);
				// 	x_b += x_step_ab;
				// 	x_c += x_step_ac;
				// 	colour_b += colour_step_ab;
				// 	colour_c += colour_step_ac;
				// 	// yC += width2d;
                //     currentScanline++;
				// }
            }
        }
    }
    
    discard;
    // fragColor = vec4(1.0, 1.0, 1.0, 1.0);
}


`.trim();
