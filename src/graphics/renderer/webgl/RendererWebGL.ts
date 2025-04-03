import type TileOverlay from '#/dash3d/type/TileOverlay.ts';
import type TileUnderlay from '#/dash3d/type/TileUnderlay.ts';
import World3D from '#/dash3d/World3D.js';
import { canvas as cpuCanvas } from '#/graphics/Canvas.ts';
import type Model from '#/graphics/Model.ts';
import Pix3D from '#/graphics/Pix3D';
import PixMap from '#/graphics/PixMap.js';
import { Renderer } from '#/graphics/renderer/Renderer.js';

import { Shader } from './Shader';
import { createProgram, ShaderProgram } from './ShaderProgram';

import { SHADER_CODE as pixMapFragShaderCode } from './shaders/fullscreen-pixmap.frag.glsl';
import { SHADER_CODE as pixMapVertShaderCode } from './shaders/fullscreen-pixmap.vert.glsl';
import { SHADER_CODE as textureFragShaderCode } from './shaders/fullscreen-texture.frag.glsl';
import { SHADER_CODE as textureVertShaderCode } from './shaders/fullscreen-texture.vert.glsl';
import mainFragShaderCode from './shaders/main.frag.glsl' with { type: 'text' };
import mainVertShaderCode from './shaders/main.vert.glsl' with { type: 'text' };
import textureTriangleVertShaderCode from './shaders/texture.vert.glsl' with { type: 'text' };
import textureTriangleFragShaderCode from './shaders/texture.frag.glsl' with { type: 'text' };

interface WEBGL_provoking_vertex {
    FIRST_VERTEX_CONVENTION_WEBGL: number;
    LAST_VERTEX_CONVENTION_WEBGL: number;
    provokingVertexWEBGL(mode: number): void;
}

function optimizeAssumingFlatsHaveSameFirstAndLastData(gl: WebGL2RenderingContext): void {
    const epv: WEBGL_provoking_vertex = gl.getExtension('WEBGL_provoking_vertex');
    if (epv) {
        epv.provokingVertexWEBGL(epv.FIRST_VERTEX_CONVENTION_WEBGL);
    }
}

const INITIAL_TRIANGLES: number = 4096;

const MAX_TEXTURE_COUNT = 50;
const MAX_TEXTURE_SIZE = 128;
const TEXTURE_SHADE_COUNT = 4;

export class RendererWebGL extends Renderer {
    drawTileUnderlay(world: World3D, underlay: TileUnderlay, level: number, tileX: number, tileZ: number): boolean {
        return false;
    }

    drawTileOverlay(world: World3D, overlay: TileOverlay, tileX: number, tileZ: number): boolean {
        return false;
    }

    startDrawModel(model: Model, yaw: number, relativeX: number, relativeY: number, relativeZ: number, bitset: number): void {
    }

    endDrawModel(model: Model, yaw: number, relativeX: number, relativeY: number, relativeZ: number, bitset: number): void {
    }

    drawModelTriangle(model: Model, index: number): boolean {
        return false;
    }

    pixMapProgram!: ShaderProgram;
    textureProgram!: ShaderProgram;
    mainProgram!: ShaderProgram;
    textureTriangleProgram!: ShaderProgram;

    viewportFramebuffer!: WebGLFramebuffer;
    viewportColorTarget!: WebGLTexture;
    viewportDepthTarget!: WebGLRenderbuffer;

    hslToRgbTexture!: WebGLTexture;

    textureArray!: WebGLTexture;

    texturesToDelete: WebGLTexture[] = [];

    texturesUsed: boolean[] = new Array(MAX_TEXTURE_COUNT).fill(false);

    isRenderingScene: boolean = false;

    triangleCount: number = 0;

    gouraudTriangleData: Uint32Array = new Uint32Array(INITIAL_TRIANGLES * 8);
    gouraudTriangleDataView: DataView = new DataView(this.gouraudTriangleData.buffer);
    gouraudTriangleCount: number = 0;

    textureTriangleData: Int32Array = new Int32Array(INITIAL_TRIANGLES * 20);
    textureTriangleDataView: DataView = new DataView(this.textureTriangleData.buffer);
    textureTriangleCount: number = 0;

    static init(container: HTMLElement, width: number, height: number): RendererWebGL {
        const canvas: HTMLCanvasElement = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        canvas.style.display = cpuCanvas.style.display;
        canvas.style.position = cpuCanvas.style.position;
        canvas.style.width = '100%';
        canvas.style.height = '100%';
        canvas.style.imageRendering = cpuCanvas.style.imageRendering;
        container.appendChild(canvas);

        const gl: WebGL2RenderingContext | null = canvas.getContext('webgl2', {
            preserveDrawingBuffer: true
        });
        if (!gl) {
            canvas.remove();
            throw new Error('WebGL2 is not supported.');
        }

        Renderer.resetRenderer();
        return new RendererWebGL(canvas, gl);
    }

    constructor(
        canvas: HTMLCanvasElement,
        readonly gl: WebGL2RenderingContext
    ) {
        super(canvas);
        this.init();
    }

    init(): void {
        this.gl.enable(this.gl.CULL_FACE);
        this.gl.depthFunc(this.gl.LEQUAL);
        
        this.gl.enable(this.gl.BLEND);
        this.gl.blendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);

        optimizeAssumingFlatsHaveSameFirstAndLastData(this.gl);

        const pixMapVertShader: Shader = new Shader(this.gl, this.gl.VERTEX_SHADER, pixMapVertShaderCode);
        const pixMapFragShader: Shader = new Shader(this.gl, this.gl.FRAGMENT_SHADER, pixMapFragShaderCode);
        this.pixMapProgram = createProgram(this.gl, [pixMapVertShader, pixMapFragShader]);
        const textureVertShader: Shader = new Shader(this.gl, this.gl.VERTEX_SHADER, textureVertShaderCode);
        const textureFragShader: Shader = new Shader(this.gl, this.gl.FRAGMENT_SHADER, textureFragShaderCode);
        this.textureProgram = createProgram(this.gl, [textureVertShader, textureFragShader]);
        const mainVertShader: Shader = new Shader(this.gl, this.gl.VERTEX_SHADER, mainVertShaderCode);
        const mainFragShader: Shader = new Shader(this.gl, this.gl.FRAGMENT_SHADER, mainFragShaderCode);
        const textureTriangleVertShader: Shader = new Shader(this.gl, this.gl.VERTEX_SHADER, textureTriangleVertShaderCode);
        const textureTriangleFragShader: Shader = new Shader(this.gl, this.gl.FRAGMENT_SHADER, textureTriangleFragShaderCode);
        this.mainProgram = createProgram(this.gl, [mainVertShader, mainFragShader]);
        this.textureTriangleProgram = createProgram(this.gl, [textureTriangleVertShader, textureTriangleFragShader]);

        const viewportWidth: number = World3D.viewportRight;
        const viewportHeight: number = World3D.viewportBottom;

        this.viewportFramebuffer = this.gl.createFramebuffer()!;
        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.viewportFramebuffer);

        this.viewportColorTarget = this.gl.createTexture()!;
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.viewportColorTarget);
        this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, viewportWidth, viewportHeight, 0, this.gl.RGBA, this.gl.UNSIGNED_BYTE, null);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);

        this.gl.framebufferTexture2D(this.gl.FRAMEBUFFER, this.gl.COLOR_ATTACHMENT0, this.gl.TEXTURE_2D, this.viewportColorTarget, 0);

        this.viewportDepthTarget = this.gl.createRenderbuffer()!;
        this.gl.bindRenderbuffer(this.gl.RENDERBUFFER, this.viewportDepthTarget);
        this.gl.renderbufferStorage(this.gl.RENDERBUFFER, this.gl.DEPTH_COMPONENT24, viewportWidth, viewportHeight);
        this.gl.framebufferRenderbuffer(this.gl.FRAMEBUFFER, this.gl.DEPTH_ATTACHMENT, this.gl.RENDERBUFFER, this.viewportDepthTarget);

        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);

        this.hslToRgbTexture = this.gl.createTexture()!;
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.hslToRgbTexture);
        this.gl.texStorage2D(this.gl.TEXTURE_2D, 1, this.gl.RGBA8, 256, 256);        
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);

        this.gl.activeTexture(this.gl.TEXTURE1);
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.hslToRgbTexture);
        this.gl.activeTexture(this.gl.TEXTURE0);


        this.textureArray = this.gl.createTexture()!;
        this.gl.bindTexture(this.gl.TEXTURE_2D_ARRAY, this.textureArray);
        this.gl.texStorage3D(this.gl.TEXTURE_2D_ARRAY, 1, this.gl.RGBA8, MAX_TEXTURE_SIZE, MAX_TEXTURE_SIZE * TEXTURE_SHADE_COUNT, MAX_TEXTURE_COUNT);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);

        // Also uploads textures
        this.setBrightness(0);

        this.gl.activeTexture(this.gl.TEXTURE2);
        this.gl.bindTexture(this.gl.TEXTURE_2D_ARRAY, this.textureArray);
        this.gl.activeTexture(this.gl.TEXTURE0);
    }

    override startFrame(): void {
        // this.gl.clearColor(0.2, 0, 0, 1);
        // this.gl.clear(this.gl.COLOR_BUFFER_BIT);
        this.texturesUsed.fill(false);
    }

    override endFrame(): void {
        for (const texture of this.texturesToDelete) {
            this.gl.deleteTexture(texture);
        }
        this.texturesToDelete.length = 0;
    }

    override updateTexture(id: number): void {
        const texels = Pix3D.getTexels(id);
        if (!texels) {
            return;
        }
        
        this.gl.bindTexture(this.gl.TEXTURE_2D_ARRAY, this.textureArray);
        this.gl.texSubImage3D(
            this.gl.TEXTURE_2D_ARRAY,
            0,
            0,
            0,
            id,
            MAX_TEXTURE_SIZE,
            MAX_TEXTURE_SIZE * TEXTURE_SHADE_COUNT,
            1,
            this.gl.RGBA,
            this.gl.UNSIGNED_BYTE,
            new Uint8Array(texels.buffer),
        );
    }

    override setBrightness(brightness: number): void {
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.hslToRgbTexture);
        this.gl.texSubImage2D(this.gl.TEXTURE_2D, 0, 0, 0, 256, 256, this.gl.RGBA, this.gl.UNSIGNED_BYTE, new Uint8Array(Pix3D.hslPal.buffer));
        
        for (let id = 0; id < MAX_TEXTURE_COUNT; id++) {
            this.updateTexture(id);
        }
    }

    override renderPixMap(pixMap: PixMap, x: number, y: number): boolean {
        this.gl.viewport(x, this.canvas.height - y - pixMap.height2d, pixMap.width2d, pixMap.height2d);

        const viewportWidth: number = World3D.viewportRight;
        const viewportHeight: number = World3D.viewportBottom;

        if (pixMap.width2d === viewportWidth && pixMap.height2d === viewportHeight) {
            this.gl.bindTexture(this.gl.TEXTURE_2D, this.viewportColorTarget);
            this.textureProgram.use();
            this.gl.drawArrays(this.gl.TRIANGLES, 0, 3);
        }

        const pixels: Uint8Array = new Uint8Array(pixMap.pixels.buffer);

        const texture: WebGLTexture = this.gl.createTexture()!;
        this.gl.bindTexture(this.gl.TEXTURE_2D, texture);
        this.gl.texStorage2D(this.gl.TEXTURE_2D, 1, this.gl.RGBA8, pixMap.width2d, pixMap.height2d);
        this.gl.texSubImage2D(this.gl.TEXTURE_2D, 0, 0, 0, pixMap.width2d, pixMap.height2d, this.gl.RGBA, this.gl.UNSIGNED_BYTE, pixels);
        // this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, pixMap.width, pixMap.height, 0, this.gl.RGBA, this.gl.UNSIGNED_BYTE, new Uint8Array(pixMap.pixels.buffer));

        this.pixMapProgram.use();
        this.gl.drawArrays(this.gl.TRIANGLES, 0, 3);

        this.texturesToDelete.push(texture);

        return true;
    }

    override startRenderScene(): void {
        this.isRenderingScene = true;
        this.triangleCount = 0;
        this.gouraudTriangleCount = 0;
        this.textureTriangleCount = 0;
    }

    override endRenderScene(): void {
        this.isRenderingScene = false;

        const viewportWidth: number = World3D.viewportRight;
        const viewportHeight: number = World3D.viewportBottom;

        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, this.viewportFramebuffer);
        this.gl.viewport(0, 0, viewportWidth, viewportHeight);

        this.gl.enable(this.gl.DEPTH_TEST);

        this.gl.clearColor(0.0, 0.0, 0.0, 1.0);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);

        // console.log('Rendering scene', this.triangleCount);

        if (this.textureTriangleCount > 0) {
            const dataPixels = this.textureTriangleCount * 5;
            const dataWidth = 4096;
            const dataHeight = Math.ceil(dataPixels / dataWidth);

            // console.log('Rendering scene texture', this.textureTriangleCount, dataWidth, dataHeight, dataPixels);

            if (dataWidth * dataHeight > this.textureTriangleData.length) {
                const newData: Int32Array = new Int32Array(dataWidth * dataHeight);
                newData.set(this.textureTriangleData);
                this.textureTriangleData = newData;
                this.textureTriangleDataView = new DataView(this.textureTriangleData.buffer);
            }

            // console.log('Rendering scene', this.textureTriangleCount);
            const texture: WebGLTexture = this.gl.createTexture()!;
            this.gl.bindTexture(this.gl.TEXTURE_2D, texture);
            this.gl.texStorage2D(this.gl.TEXTURE_2D, 1, this.gl.RGBA32I, dataWidth, dataHeight);
            this.gl.texSubImage2D(this.gl.TEXTURE_2D, 0, 0, 0, dataWidth, dataHeight, this.gl.RGBA_INTEGER, this.gl.INT, this.textureTriangleData);

            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.NEAREST);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.NEAREST);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);

            this.textureTriangleProgram.use();

            const textureTranslucent = new Int32Array(Pix3D.textureTranslucent.length);
            for (let i = 0; i < textureTranslucent.length; i++) {
                textureTranslucent[i] = Pix3D.textureTranslucent[i] ? 1 : 0;
            }

            this.gl.uniform1iv(this.textureTriangleProgram.getUniformLocation('u_textureTranslucent'), textureTranslucent);
            this.gl.uniform1f(this.textureTriangleProgram.getUniformLocation('u_triangleCount'), this.triangleCount);
            this.gl.uniform1i(this.textureTriangleProgram.getUniformLocation('u_triangleData'), 0);
            // this.gl.uniform1i(this.textureTriangleProgram.getUniformLocation('u_hslToRgb'), 1);
            this.gl.uniform1i(this.textureTriangleProgram.getUniformLocation('u_textures'), 2);

            this.gl.drawArrays(this.gl.TRIANGLES, 0, this.textureTriangleCount * 3);

            this.texturesToDelete.push(texture);
        }

        if (this.gouraudTriangleCount > 0) {
            const dataPixels = this.gouraudTriangleCount * 2;
            const dataWidth = 4096;
            const dataHeight = Math.ceil(dataPixels / dataWidth);

            // console.log('Rendering scene gouraud', this.gouraudTriangleCount, dataWidth, dataHeight, dataPixels);

            if (dataWidth * dataHeight > this.gouraudTriangleData.length) {
                const newData: Uint32Array = new Uint32Array(dataWidth * dataHeight);
                newData.set(this.gouraudTriangleData);
                this.gouraudTriangleData = newData;
                this.gouraudTriangleDataView = new DataView(this.gouraudTriangleData.buffer);
            }

            const texture: WebGLTexture = this.gl.createTexture()!;
            this.gl.bindTexture(this.gl.TEXTURE_2D, texture);
            this.gl.texStorage2D(this.gl.TEXTURE_2D, 1, this.gl.RGBA32UI, dataWidth, dataHeight);
            this.gl.texSubImage2D(this.gl.TEXTURE_2D, 0, 0, 0, dataWidth, dataHeight, this.gl.RGBA_INTEGER, this.gl.UNSIGNED_INT, this.gouraudTriangleData);

            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.NEAREST);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.NEAREST);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
            this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);

            this.mainProgram.use();

            this.gl.uniform1f(this.mainProgram.getUniformLocation('u_triangleCount'), this.triangleCount);
            this.gl.uniform1i(this.mainProgram.getUniformLocation('u_triangleData'), 0);
            this.gl.uniform1i(this.mainProgram.getUniformLocation('u_hslToRgb'), 1);

            this.gl.drawArrays(this.gl.TRIANGLES, 0, this.gouraudTriangleCount * 3);

            this.texturesToDelete.push(texture);
        }

        this.gl.bindFramebuffer(this.gl.FRAMEBUFFER, null);
        
        this.gl.disable(this.gl.DEPTH_TEST);
    }

    override fillTriangle(x0: number, x1: number, x2: number, y0: number, y1: number, y2: number, color: number, hsl: number): boolean {
        if (!this.isRenderingScene) {
            return false;
        }

        if ((this.gouraudTriangleCount + 1) * 8 >= this.gouraudTriangleData.length) {
            const newData: Uint32Array = new Uint32Array(this.gouraudTriangleData.length * 2);
            newData.set(this.gouraudTriangleData);
            this.gouraudTriangleData = newData;
            this.gouraudTriangleDataView = new DataView(this.gouraudTriangleData.buffer);
        }

        let offset: number = this.gouraudTriangleCount * 8;

        x0 += 32768;
        x1 += 32768;
        x2 += 32768;
        y0 += 32768;
        y1 += 32768;
        y2 += 32768;

        this.gouraudTriangleDataView.setUint32(offset++ * 4, (x0 << 16) | x1, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, (x2 << 16) | y0, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, (y1 << 16) | y2, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, (hsl << 16) | hsl, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, hsl, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, this.triangleCount, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, Pix3D.alpha, true);

        this.triangleCount++;
        this.gouraudTriangleCount++;

        return true;
    }

    override fillGouraudTriangle(xA: number, xB: number, xC: number, yA: number, yB: number, yC: number, colorA: number, colorB: number, colorC: number): boolean {
        if (!this.isRenderingScene) {
            return false;
        }

        if ((this.gouraudTriangleCount + 1) * 8 >= this.gouraudTriangleData.length) {
            const newData: Uint32Array = new Uint32Array(this.gouraudTriangleData.length * 2);
            newData.set(this.gouraudTriangleData);
            this.gouraudTriangleData = newData;
            this.gouraudTriangleDataView = new DataView(this.gouraudTriangleData.buffer);
        }

        let offset: number = this.gouraudTriangleCount * 8;
        
        xA += 32768;
        xB += 32768;
        xC += 32768;
        yA += 32768;
        yB += 32768;
        yC += 32768;

        this.gouraudTriangleDataView.setUint32(offset++ * 4, (xA << 16) | xB, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, (xC << 16) | yA, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, (yB << 16) | yC, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, (colorA << 16) | colorB, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, colorC, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, this.triangleCount, true);
        this.gouraudTriangleDataView.setUint32(offset++ * 4, Pix3D.alpha, true);

        this.triangleCount++;
        this.gouraudTriangleCount++;

        return true;
    }

    override fillTexturedTriangle(
        xA: number,
        xB: number,
        xC: number,
        yA: number,
        yB: number,
        yC: number,
        shadeA: number,
        shadeB: number,
        shadeC: number,
        originX: number,
        originY: number,
        originZ: number,
        txB: number,
        txC: number,
        tyB: number,
        tyC: number,
        tzB: number,
        tzC: number,
        texture: number
    ): boolean {
        if (!this.isRenderingScene) {
            return false;
        }

        // Flag texture as used for animated textures
        if (!this.texturesUsed[texture]) {
            Pix3D.textureCycle[texture] = Pix3D.cycle++;
            this.texturesUsed[texture] = true;
        }

        // if (true) {
        //     this.fillGouraudTriangle(xA, xB, xC, yA, yB, yC, shadeA, shadeB, shadeC);
        //     return true;
        // }

        if ((this.textureTriangleCount + 1) * 20 >= this.textureTriangleData.length) {
            const newData: Int32Array = new Int32Array(this.textureTriangleData.length * 2);
            newData.set(this.textureTriangleData);
            this.textureTriangleData = newData;
            this.textureTriangleDataView = new DataView(this.textureTriangleData.buffer);
        }

        let offset: number = this.textureTriangleCount * 20;

        this.textureTriangleDataView.setInt32(offset++ * 4, xA, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, xB, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, xC, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, yA, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, yB, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, yC, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, shadeA, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, shadeB, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, shadeC, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, originX, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, originY, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, originZ, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, txB, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, txC, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, tyB, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, tyC, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, tzB, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, tzC, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, texture, true);
        this.textureTriangleDataView.setInt32(offset++ * 4, this.triangleCount, true);

        this.triangleCount++;
        this.textureTriangleCount++;

        return true;
    }

    override destroy(): void { }
}
