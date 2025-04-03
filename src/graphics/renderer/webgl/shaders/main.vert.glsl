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

    // We have to create a larger triangle because the runescape rasterizer is different 
    // there will be missing pixels around the edges of the triangle if we don't
    // there might a better way to do this

    vec2 p0 = vec2(v_data0.x, v_data0.w);
    vec2 p1 = vec2(v_data0.y, v_data1.x);
    vec2 p2 = vec2(v_data0.z, v_data1.y);

    // Calculate the bounding box of the triangle
    float minX = min(p0.x, min(p1.x, p2.x));
    float maxX = max(p0.x, max(p1.x, p2.x));
    float minY = min(p0.y, min(p1.y, p2.y));
    float maxY = max(p0.y, max(p1.y, p2.y));

    // Calculate triangle that contains the bounding box
    vec2 vertices[3] = vec2[3](
        vec2(minX, minY),
        vec2(minX, maxY + maxY - minY),
        vec2(maxX + maxX - minX, minY)
    );

    float depth = 1.0 - float(v_data2.y) / u_triangleCount;

    int vertexIndex = gl_VertexID % 3;

    gl_Position = vec4(vertices[vertexIndex] * 2.0 / dimensions - 1.0, depth, 1.0);
    
    // flip y
    gl_Position.y *= -1.0;

    // gl_Position = vec4(vertices[vertexIndex], depth, 1.0);
}
