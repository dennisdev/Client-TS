export const SHADER_CODE: string = `
#version 300 es

precision highp float;

uniform highp sampler2D u_frame;

in vec2 v_texCoord;

out vec4 fragColor;

void main() {
    fragColor = vec4(texture(u_frame, v_texCoord).rgb, 1.0);
}
`.trim();
