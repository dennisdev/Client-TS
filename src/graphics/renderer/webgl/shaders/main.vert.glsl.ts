export const SHADER_CODE: string = `
#version 300 es

precision highp float;
precision highp int;

uniform highp usampler2D u_triangleData;

flat out ivec3 xs;
flat out ivec3 ys;
flat out ivec3 colors;

const float width = 512.0;
const float height = 334.0;
const vec2 dimensions = vec2(width, height);

const vec2 vertices[3] = vec2[3](
    vec2(-1, -1), 
    vec2( 3, -1), 
    vec2(-1,  3)
);

void main() {
    int triangleIndex = gl_VertexID / 3;

    uvec4 triangleData = texelFetch(u_triangleData, ivec2(triangleIndex, 0), 0);
    xs = ivec3(
        int(triangleData.x >> 20u),
        int((triangleData.x >> 8u) & 0xFFFu),
        (int(triangleData.x & 0xFFu) << 4) | int(triangleData.y & 0xFFu)
    ) - 2048;
    ys = ivec3(
        int(triangleData.y >> 20u),
        int((triangleData.y >> 8u) & 0xFFFu),
        int(triangleData.z >> 16u)
    ) - 2048;
    colors = ivec3(
        int(triangleData.z & 0xFFFFu),
        int(triangleData.w >> 16u),
        int(triangleData.w & 0xFFFFu)
    );

    int vertexIndex = gl_VertexID % 3;

    vec2 screenPos = vec2(xs[vertexIndex], ys[vertexIndex]);
    screenPos += 0.5;
    gl_Position = vec4(screenPos * 2.0 / dimensions - 1.0, 0.0, 1.0);
    
    // flip y
    gl_Position.y *= -1.0;

    gl_Position = vec4(vertices[vertexIndex], 0.0, 1.0);
}
`.trim();
