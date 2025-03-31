export const SHADER_CODE: string = `
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

const int boundBottom = height;

const int centerX = width / 2;

vec3 hslToRgb(int hsl) {
    return texelFetch(u_hslToRgb, ivec2(hsl % 256, hsl / 256), 0).bgr;
}

int reciprocal15(int value) {
    return 32768 / value;
}

bool isOutsideScanline(int xA, int xB) {
    // return false;
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
    int texture = v_data4.z;

    int minScanlineY = max(min(y_a, min(y_b, y_c)), 0);
    int maxScanlineY = max(y_a, max(y_b, y_c));
    int scanline_y = height - int(gl_FragCoord.y) - 1 - minScanlineY;
    if (scanline_y < 0 || scanline_y > maxScanlineY - minScanlineY) {
        discard;
    }

    fragColor.a = 1.0;

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
        colour_step_ab = ((shade_b - shade_a) << 15) / (y_b - y_a);
	}

	int x_step_bc = 0;
	int colour_step_bc = 0;
	if (y_c != y_b) {
        x_step_bc = ((x_c - x_b) << 16) / (y_c - y_b);
        colour_step_bc = ((shade_c - shade_b) << 15) / (y_c - y_b);
	}

	int x_step_ac = 0;
	int colour_step_ac = 0;
	if (y_c != y_a) {
        x_step_ac = ((x_a - x_c) << 16) / (y_a - y_c);
        colour_step_ac = ((shade_a - shade_c) << 15) / (y_a - y_c);
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
                shade_c = shade_a <<= 15;
                if (y_a < 0) {
                    x_c -= x_step_ac * y_a;
                    x_a -= x_step_ab * y_a;
                    shade_c -= colour_step_ac * y_a;
                    shade_a -= colour_step_ab * y_a;
                    y_a = 0;
                }

                x_b <<= 16;
                shade_b <<= 15;
                if (y_b < 0) {
                    x_b -= x_step_bc * y_b;
                    shade_b -= colour_step_bc * y_b;
                    y_b = 0;
                }

                if (y_a != y_b && x_step_ac < x_step_ab || y_a == y_b && x_step_ac > x_step_bc) {
                    y_c -= y_b;
                    y_b -= y_a;
                    // yA = lineOffset[yA];

                    while (--y_b >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_a >> 16;
                            int scanlineXB = x_c >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_a >> 7);
                            return;
                        }
                        // gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yA, 0);
                        x_c += x_step_ac;
                        x_a += x_step_ab;
                        shade_c += colour_step_ac;
                        shade_a += colour_step_ab;
                        // yA += width2d;
                        currentScanline++;
                    }
                    while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_c >> 16;
                            int scanlineXB = x_b >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_b >> 7);
                            return;
                        }
                        // gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yA, 0);
                        x_c += x_step_ac;
                        x_b += x_step_bc;
                        shade_c += colour_step_ac;
                        shade_b += colour_step_bc;
                        // yA += width2d;
                        currentScanline++;
                    }
                } else {
                    y_c -= y_b;
                    y_b -= y_a;
                    // yA = lineOffset[yA];

                    while (--y_b >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_a >> 16;
                            int scanlineXB = x_c >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_c >> 7);
                            return;
                        }
                        // gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yA, 0);
                        x_c += x_step_ac;
                        x_a += x_step_ab;
                        shade_c += colour_step_ac;
                        shade_a += colour_step_ab;
                        // yA += width2d;
                        currentScanline++;
                    }
                    while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_b >> 16;
                            int scanlineXB = x_c >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_c >> 7);
                            return;
                        }
                        // gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yA, 0);
                        x_c += x_step_ac;
                        x_b += x_step_bc;
                        shade_c += colour_step_ac;
                        shade_b += colour_step_bc;
                        // yA += width2d;
                        currentScanline++;
                    }
                }
            } else {
                x_b = x_a <<= 16;
                shade_b = shade_a <<= 15;
                if (y_a < 0) {
                    x_b -= x_step_ac * y_a;
                    x_a -= x_step_ab * y_a;
                    shade_b -= colour_step_ac * y_a;
                    shade_a -= colour_step_ab * y_a;
                    y_a = 0;
                }

                x_c <<= 16;
                shade_c <<= 15;
                if (y_c < 0) {
                    x_c -= x_step_bc * y_c;
                    shade_c -= colour_step_bc * y_c;
                    y_c = 0;
                }

                if (y_a != y_c && x_step_ac < x_step_ab || y_a == y_c && x_step_bc > x_step_ab) {
                    y_b -= y_c;
                    y_c -= y_a;
                    // yA = lineOffset[yA];

                    while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_b >> 16;
                            int scanlineXB = x_a >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_a >> 7);
                            return;
                        }
                        // gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yA, 0);
                        x_b += x_step_ac;
                        x_a += x_step_ab;
                        shade_b += colour_step_ac;
                        shade_a += colour_step_ab;
                        // yA += width2d;
                        currentScanline++;
                    }
                    while (--y_b >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_c >> 16;
                            int scanlineXB = x_a >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_a >> 7);
                            return;
                        }
                        // gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yA, 0);
                        x_c += x_step_bc;
                        x_a += x_step_ab;
                        shade_c += colour_step_bc;
                        shade_a += colour_step_ab;
                        // yA += width2d;
                        currentScanline++;
                    }
                } else {
                    y_b -= y_c;
                    y_c -= y_a;
                    // yA = lineOffset[yA];

                    while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_a >> 16;
                            int scanlineXB = x_b >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_b >> 7);
                            return;
                        }
                        // gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yA, 0);
                        x_b += x_step_ac;
                        x_a += x_step_ab;
                        shade_b += colour_step_ac;
                        shade_a += colour_step_ab;
                        // yA += width2d;
                        currentScanline++;
                    }
                    while (--y_b >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_a >> 16;
                            int scanlineXB = x_c >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_c >> 7);
                            return;
                        }
                        // gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yA, 0);
                        x_c += x_step_bc;
                        x_a += x_step_ab;
                        shade_c += colour_step_bc;
                        shade_a += colour_step_ab;
                        // yA += width2d;
                        currentScanline++;
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
				shade_a = shade_b <<= 15;
				if (y_b < 0) {
					x_a -= x_step_ab * y_b;
					x_b -= x_step_bc * y_b;
					shade_a -= colour_step_ab * y_b;
					shade_b -= colour_step_bc * y_b;
					y_b = 0;
				}

				x_c <<= 16;
				shade_c <<= 15;
				if (y_c < 0) {
					x_c -= x_step_ac * y_c;
					shade_c -= colour_step_ac * y_c;
					y_c = 0;
				}

				if (y_b != y_c && x_step_ab < x_step_bc || y_b == y_c && x_step_ab > x_step_ac) {
					y_a -= y_c;
					y_c -= y_b;
					// yB = lineOffset[yB];

					while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_a >> 16;
                            int scanlineXB = x_b >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_b >> 7);
                            return;
                        }
						// gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yB, 0);
						x_a += x_step_ab;
						x_b += x_step_bc;
						shade_a += colour_step_ab;
						shade_b += colour_step_bc;
						// yB += width2d;
                        currentScanline++;
					}
					while (--y_a >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_a >> 16;
                            int scanlineXB = x_c >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_c >> 7);
                            return;
                        }
						// gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yB, 0);
						x_a += x_step_ab;
						x_c += x_step_ac;
						shade_a += colour_step_ab;
						shade_c += colour_step_ac;
						// yB += width2d;
                        currentScanline++;
					}
				} else {
					y_a -= y_c;
					y_c -= y_b;
					// yB = lineOffset[yB];

					while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_b >> 16;
                            int scanlineXB = x_a >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_a >> 7);
                            return;
                        }
						// gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yB, 0);
						x_a += x_step_ab;
						x_b += x_step_bc;
						shade_a += colour_step_ab;
						shade_b += colour_step_bc;
						// yB += width2d;
                        currentScanline++;
					}
					while (--y_a >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_c >> 16;
                            int scanlineXB = x_a >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_a >> 7);
                            return;
                        }
						// gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yB, 0);
						x_a += x_step_ab;
						x_c += x_step_ac;
						shade_a += colour_step_ab;
						shade_c += colour_step_ac;
						// yB += width2d;
                        currentScanline++;
					}
				}
			} else {
				x_c = x_b <<= 16;
				shade_c = shade_b <<= 15;
				if (y_b < 0) {
					x_c -= x_step_ab * y_b;
					x_b -= x_step_bc * y_b;
					shade_c -= colour_step_ab * y_b;
					shade_b -= colour_step_bc * y_b;
					y_b = 0;
				}

				x_a <<= 16;
				shade_a <<= 15;
				if (y_a < 0) {
					x_a -= x_step_ac * y_a;
					shade_a -= colour_step_ac * y_a;
					y_a = 0;
				}

				if (x_step_ab < x_step_bc) {
					y_c -= y_a;
					y_a -= y_b;
					// yB = lineOffset[yB];

					while (--y_a >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_c >> 16;
                            int scanlineXB = x_b >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_b >> 7);
                            return;
                        }
						// gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yB, 0);
						x_c += x_step_ab;
						x_b += x_step_bc;
						shade_c += colour_step_ab;
						shade_b += colour_step_bc;
						// yB += width2d;
                        currentScanline++;
					}
					while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_a >> 16;
                            int scanlineXB = x_b >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_b >> 7);
                            return;
                        }
						// gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yB, 0);
						x_a += x_step_ac;
						x_b += x_step_bc;
						shade_a += colour_step_ac;
						shade_b += colour_step_bc;
						// yB += width2d;
                        currentScanline++;
					}
				} else {
					y_c -= y_a;
					y_a -= y_b;
					// yB = lineOffset[yB];

					while (--y_a >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_b >> 16;
                            int scanlineXB = x_c >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_c >> 7);
                            return;
                        }
						// gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yB, 0);
						x_c += x_step_ab;
						x_b += x_step_bc;
						shade_c += colour_step_ab;
						shade_b += colour_step_bc;
						// yB += width2d;
                        currentScanline++;
					}
					while (--y_c >= 0) {
                        if (currentScanline == scanline_y) {
                            int scanlineXA = x_b >> 16;
                            int scanlineXB = x_a >> 16;
                            if (isOutsideScanline(scanlineXA, scanlineXB)) {
                                discard;
                            }
                            fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_a >> 7);
                            return;
                        }
						// gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yB, 0);
						x_a += x_step_ac;
						x_b += x_step_bc;
						shade_a += colour_step_ac;
						shade_b += colour_step_bc;
						// yB += width2d;
                        currentScanline++;
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
			shade_b = shade_c <<= 15;
			if (y_c < 0) {
				x_b -= x_step_bc * y_c;
				x_c -= x_step_ac * y_c;
				shade_b -= colour_step_bc * y_c;
				shade_c -= colour_step_ac * y_c;
				y_c = 0;
			}

			x_a <<= 16;
			shade_a <<= 15;
			if (y_a < 0) {
				x_a -= x_step_ab * y_a;
				shade_a -= colour_step_ab * y_a;
				y_a = 0;
			}

            if (x_step_bc < x_step_ac) {
				y_b -= y_a;
				y_a -= y_c;
				// yC = lineOffset[yC];

				while (--y_a >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_c >> 7);
                        return;
                    }
					// gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yC, 0);
					x_b += x_step_bc;
					x_c += x_step_ac;
					shade_b += colour_step_bc;
					shade_c += colour_step_ac;
					// yC += width2d;
                    currentScanline++;
				}
				while (--y_b >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_a >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_a >> 7);
                        return;
                    }
					// gouraudRaster(xB >> 16, xA >> 16, colorB >> 7, colorA >> 7, data, yC, 0);
					x_b += x_step_bc;
					x_a += x_step_ab;
					shade_b += colour_step_bc;
					shade_a += colour_step_ab;
					// yC += width2d;
                    currentScanline++;
				}
			} else {
				y_b -= y_a;
				y_a -= y_c;
				// yC = lineOffset[yC];

				while (--y_a >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_c >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_b >> 7);
                        return;
                    }
					// gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yC, 0);
					x_b += x_step_bc;
					x_c += x_step_ac;
					shade_b += colour_step_bc;
					shade_c += colour_step_ac;
					// yC += width2d;
                    currentScanline++;
				}
				while (--y_b >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_b >> 7);
                        return;
                    }
					// gouraudRaster(xA >> 16, xB >> 16, colorA >> 7, colorB >> 7, data, yC, 0);
					x_b += x_step_bc;
					x_a += x_step_ab;
					shade_b += colour_step_bc;
					shade_a += colour_step_ab;
					// yC += width2d;
                    currentScanline++;
				}
			}
        } else {
			x_a = x_c <<= 16;
			shade_a = shade_c <<= 15;
			if (y_c < 0) {
				x_a -= x_step_bc * y_c;
				x_c -= x_step_ac * y_c;
				shade_a -= colour_step_bc * y_c;
				shade_c -= colour_step_ac * y_c;
				y_c = 0;
			}

			x_b <<= 16;
			shade_b <<= 15;
			if (y_b < 0) {
				x_b -= x_step_ab * y_b;
				shade_b -= colour_step_ab * y_b;
				y_b = 0;
			}

			if (x_step_bc < x_step_ac) {
                y_a -= y_b;
                y_b -= y_c;

                while (--y_b >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_a >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_a >> 7, shade_c >> 7);
                        return;
                    }
                    // gouraudRaster(xA >> 16, xC >> 16, colorA >> 7, colorC >> 7, data, yC, 0);
                    x_a += x_step_bc;
                    x_c += x_step_ac;
                    shade_a += colour_step_bc;
                    shade_c += colour_step_ac;
                    // yC += width2d;
                    currentScanline++;
                }
                while (--y_a >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_b >> 16;
                        int scanlineXB = x_c >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_b >> 7, shade_c >> 7);
                        return;
                    }
                    // gouraudRaster(xB >> 16, xC >> 16, colorB >> 7, colorC >> 7, data, yC, 0);
                    x_b += x_step_ab;
                    x_c += x_step_ac;
                    shade_b += colour_step_ab;
                    shade_c += colour_step_ac;
                    // yC += width2d;
                    currentScanline++;
                }
            } else {
				y_a -= y_b;
				y_b -= y_c;
					
                while (--y_b >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_c >> 16;
                        int scanlineXB = x_a >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_a >> 7);
                        return;
                    }
					// gouraudRaster(xC >> 16, xA >> 16, colorC >> 7, colorA >> 7, data, yC, 0);
					x_a += x_step_bc;
					x_c += x_step_ac;
					shade_a += colour_step_bc;
					shade_c += colour_step_ac;
					// yC += width2d;
                    currentScanline++;
				}
				while (--y_a >= 0) {
                    if (currentScanline == scanline_y) {
                        int scanlineXA = x_c >> 16;
                        int scanlineXB = x_b >> 16;
                        if (isOutsideScanline(scanlineXA, scanlineXB)) {
                            discard;
                        }
                        fragColor.rgb = getScanlineColor(scanlineXA, scanlineXB, shade_c >> 7, shade_b >> 7);
                        return;
                    }
					// gouraudRaster(xC >> 16, xB >> 16, colorC >> 7, colorB >> 7, data, yC, 0);
					x_b += x_step_ab;
					x_c += x_step_ac;
					shade_b += colour_step_ab;
					shade_c += colour_step_ac;
					// yC += width2d;
                    currentScanline++;
				}
            }
        }
    }
    
    discard;
    // fragColor = vec4(1.0, 1.0, 1.0, 1.0);
}

`.trim();
