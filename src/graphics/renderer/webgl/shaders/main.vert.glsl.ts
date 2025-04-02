export const SHADER_CODE: string = `
#version 300 es

precision highp float;
precision highp int;

uniform highp float u_triangleCount;

uniform highp isampler2D u_triangleData;

flat out ivec4 v_data0;
flat out ivec4 v_data1;
flat out ivec4 v_data2;

const float width = 512.0;
const float height = 334.0;
const vec2 dimensions = vec2(width, height);

const vec2 vertices[3] = vec2[3](
    vec2(-1, -1), 
    vec2( 3, -1), 
    vec2(-1,  3)
);

ivec4 fetchData(int index) {
    return texelFetch(u_triangleData, ivec2(index % 4096, index / 4096), 0);
}

void main() {
    int triangleIndex = gl_VertexID / 3 * 3;

    v_data0 = fetchData(triangleIndex);
    v_data1 = fetchData(triangleIndex + 1);
    v_data2 = fetchData(triangleIndex + 2);

    float depth = 1.0 - float(v_data2.y) / u_triangleCount;

    int vertexIndex = gl_VertexID % 3;

    // vec2 screenPos = vec2(xs[vertexIndex], ys[vertexIndex]);
    // screenPos += 0.5;
    // gl_Position = vec4(screenPos * 2.0 / dimensions - 1.0, 0.0, 1.0);
    
    // // flip y
    // gl_Position.y *= -1.0;

    gl_Position = vec4(vertices[vertexIndex], depth, 1.0);
}
`.trim();
