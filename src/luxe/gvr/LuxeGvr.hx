package luxe.gvr;

import cpp.*;
import gvr.c.*;
import snow.modules.opengl.GL;
import snow.types.Types;
import phoenix.Renderer;
import phoenix.RenderPath;
import phoenix.RenderState;
import luxe.gvr.GvrRenderPath;
import luxe.*;

class LuxeGvr {
	public var head(default, null):Head;
	public var mode(get, set):RenderMode;
	public var orientation(default, set):Orientation;
	
	var cameras:Array<Camera>;
	var context:Context;
	var viewportList:BufferViewportList;
	var leftEyeViewport:BufferViewport;
	var rightEyeViewport:BufferViewport;
	var swapChain:SwapChain;
	var frame:Frame;
	var rawHead:Mat4f;
	
	var originalRenderPath:RenderPath;
	var originalCamera:Camera;
	var renderPath:GvrRenderPath;
	var monoTarget:MonoRenderTarget;
	var stereoTarget:GvrRenderTarget;
	
	var tempMatrix:Matrix = new Matrix();
	var landscapeInited = false;
	
	static var TO_RADIANS = Math.PI / 180;
	
	public function new(orientation) {
		
		context = Gvr.create();
		Gvr.initializeGl(context);
		viewportList = Gvr.bufferViewportListCreate(context);
		leftEyeViewport = Gvr.bufferViewportCreate(context);
		rightEyeViewport = Gvr.bufferViewportCreate(context);
		swapChain = Gvr.swapChainCreate(context, 1);
		Luxe.renderer.state.bindFramebuffer();
		Luxe.renderer.state.bindRenderbuffer();
		
		landscapeInited = switch orientation {
			#if ios case Portrait | UpsideDown: false; #end
			default: true;
		}
		
		head = new Head();
		this.orientation = orientation;
		
		originalCamera = Luxe.camera;
		
		var r = Luxe.screen.width / Luxe.screen.height;
		Luxe.camera = new Camera({
			name: 'head',
			projection: phoenix.Camera.ProjectionType.perspective,
			fov: 90, near: 0.1, far: 1000,
			aspect: Luxe.screen.width / Luxe.screen.height,
			cull_backfaces: false,
			depth_test: true,
		});
		
		cameras = [
			new Camera({
				name: 'left_eye',
				projection: custom,
				cull_backfaces: false,
				depth_test: true,
			}),
			new Camera({
				name: 'right_eye',
				projection: custom,
				cull_backfaces: false,
				depth_test: true,
			}),
		];
		
		
		originalRenderPath = Luxe.renderer.render_path;
		Luxe.renderer.render_path = renderPath = new GvrRenderPath(Luxe.renderer, Luxe.camera, cameras[0], cameras[1]);
		
		trace(
			Luxe.core.app.runtime.window_width(),
			Luxe.core.app.runtime.window_height(),
			Luxe.screen.w,
			Luxe.screen.h
		);
		trace('create monoTarget:', 
			Luxe.renderer.default_target.width,
			Luxe.renderer.default_target.height
		);
			
		monoTarget = new MonoRenderTarget(
			Luxe.renderer.default_target.width,
			Luxe.renderer.default_target.height,
			Luxe.renderer.default_target.viewport_scale,
			Luxe.renderer.default_target.framebuffer,
			Luxe.renderer.default_target.renderbuffer
		);
		Luxe.renderer.target = stereoTarget = new GvrRenderTarget(0, 0);
		
		updateViewport();
		
		Luxe.on(luxe.Ev.tickstart, ontickstart);
		Luxe.on(luxe.Ev.postrender, onpostrender);
		Luxe.on(luxe.Ev.windowresized, function(e:WindowEvent) {
			monoTarget.width = Std.int(e.x * monoTarget.viewport_scale);
			monoTarget.height = Std.int(e.y * monoTarget.viewport_scale);
			Luxe.camera.viewport.set(0, 0, e.x, e.y);
			Luxe.camera.view.set_perspective({	
				fov: 90, near: 0.1, far: 1000,
				aspect: e.x / e.y,
				cull_backfaces: false,
				depth_test: true,
			});
			// trace('.................', e.y, r, monoTarget.height);
		});
	}
	
	function updateViewport() {
		
		var size = Gvr.swapChainGetBufferSize(swapChain, 0);
		stereoTarget.width = Std.int(size.width / 2);
		stereoTarget.height = Std.int(size.height);
		cameras[0].viewport.set(0, 0, stereoTarget.width, stereoTarget.height);
		cameras[1].viewport.set(stereoTarget.width, 0, stereoTarget.width, stereoTarget.height);
		
	}
	
	var prevh:Float;
	function ontickstart(_) {	
		Gvr.getRecommendedBufferViewports(context, viewportList);
		Gvr.bufferViewportListGetItem(viewportList, 0, leftEyeViewport);
		Gvr.bufferViewportListGetItem(viewportList, 1, rightEyeViewport);
		var time = Gvr.getTimePointNow();
		rawHead = Gvr.getHeadSpaceFromStartSpaceRotation(context, time);
		
		// updateViewport();
		
		mat4fToMatrix(rawHead, head.raw);
		head.refresh();
		
		if(mode == Stereo) {
			var leftEye = Gvr.getEyeFromHeadMatrix(context, 0);
			var rightEye = Gvr.getEyeFromHeadMatrix(context, 1);
			var leftEyeMatrix = mat4fToMatrix(leftEye).multiply(head.matrix);
			var rightEyeMatrix = mat4fToMatrix(rightEye).multiply(head.matrix);
		
			cameras[0].rotation.setFromRotationMatrix(leftEyeMatrix.inverse());
			cameras[0].pos.set_xyz(0, 0, 0).applyProjection(leftEyeMatrix);
			cameras[1].rotation.setFromRotationMatrix(rightEyeMatrix.inverse());
			cameras[1].pos.set_xyz(0, 0, 0).applyProjection(rightEyeMatrix);
			
			cameras[0].view.projection_matrix = perspective(Gvr.bufferViewportGetSourceFov(leftEyeViewport), 0.1, 100);
			cameras[0].view.proj_arr = cameras[0].view.projection_matrix.float32array();
			cameras[1].view.projection_matrix = perspective(Gvr.bufferViewportGetSourceFov(rightEyeViewport), 0.1, 100);
			cameras[1].view.proj_arr = cameras[1].view.projection_matrix.float32array();
			cameras[0].view.depth_test = cameras[1].view.depth_test = true;
			@:privateAccess Luxe.renderer.state.depth_test = false;
			
			frame = Gvr.swapChainAcquireFrame(swapChain);
			stereoTarget.framebuffer.id = Gvr.frameGetFramebufferObject(frame, 0);
			Gvr.frameBindBuffer(frame, 0);
		} else {
			Luxe.camera.rotation.setFromRotationMatrix(head.inverse);
			Luxe.camera.view.depth_test = true;
		}
		
		GL.enable(GL.BLEND);
		Luxe.renderer.blend_mode(src_alpha, one_minus_src_alpha);
	}
	
	function onpostrender(_) {
		if(mode == Stereo) {
			Gvr.frameUnbind(frame);
			Gvr.frameSubmit(frame, viewportList, rawHead);
			
			#if ios
			Luxe.renderer.state.bindFramebuffer();
			Luxe.renderer.state.bindRenderbuffer();
			#end
		}
	}
	
	public function destroy() {
		// TODO
		// Gvr.destroy(RawPointer.addressOf(context.raw));
		// context = null;
		
		Luxe.camera.destroy();
		while(cameras.length > 0) cameras.pop().destroy();
		
		Luxe.camera = originalCamera;
		Luxe.off(luxe.Ev.tickstart, ontickstart);
		Luxe.off(luxe.Ev.postrender, onpostrender);
		Luxe.renderer.render_path = originalRenderPath;
		Luxe.renderer.target = Luxe.renderer.backbuffer;
	}
	
	function mat4fToMatrix(matrix:Mat4f, ?into:Matrix) {
		if(into == null) into = new Matrix();
		return into.set(
			matrix.m[0][0], matrix.m[0][1], matrix.m[0][2], matrix.m[0][3],
			matrix.m[1][0], matrix.m[1][1], matrix.m[1][2], matrix.m[1][3],
			matrix.m[2][0], matrix.m[2][1], matrix.m[2][2], matrix.m[2][3],
			matrix.m[3][0], matrix.m[3][1], matrix.m[3][2], matrix.m[3][3]
		);
	}
	
	function perspective(fov:Rectf, z_near:Float, z_far:Float) {

		var x_left = -Math.tan(fov.left * TO_RADIANS) * z_near;
		var x_right = Math.tan(fov.right * TO_RADIANS) * z_near;
		var y_bottom = -Math.tan(fov.bottom * TO_RADIANS) * z_near;
		var y_top = Math.tan(fov.top * TO_RADIANS) * z_near;
		
		var X = (2 * z_near) / (x_right - x_left);
		var Y = (2 * z_near) / (y_top - y_bottom);
		var A = (x_right + x_left) / (x_right - x_left);
		var B = (y_top + y_bottom) / (y_top - y_bottom);
		var C = (z_near + z_far) / (z_near - z_far);
		var D = (2 * z_near * z_far) / (z_near - z_far);
		
		return new Matrix(
			X, 0, A, 0,
			0, Y, B, 0,
			0, 0, C, D,
			0, 0, -1, 0
		);
	}
	
	inline function get_mode()
		return renderPath.mode;
		
	function set_mode(v) {
		Luxe.renderer.target = switch v {
			case Mono: monoTarget;
			case Stereo: stereoTarget;
		}
		return renderPath.mode = v;
	}
	
	function set_orientation(v:Orientation) {
		if(!landscapeInited) {
			// HACK: somehow we must init gvr while the device is in landscape orientation
			// otherwise it doesn't prepare a correctly sized buffer
			switch v {
				case Portrait | UpsideDown: // do nothing
				default:
					landscapeInited = true;
					context = Gvr.create();
					Gvr.initializeGl(context);
					viewportList = Gvr.bufferViewportListCreate(context);
					leftEyeViewport = Gvr.bufferViewportCreate(context);
					rightEyeViewport = Gvr.bufferViewportCreate(context);
					swapChain = Gvr.swapChainCreate(context, 1);
					Luxe.renderer.state.bindFramebuffer();
					Luxe.renderer.state.bindRenderbuffer();
					
					updateViewport();
			}
		}
		
		switch v {
			case Portrait:
				head.transform.orientation.makeRotationAxis(new Vector(0, 0, 1), -Math.PI/2);
			case UpsideDown:
				head.transform.orientation.makeRotationAxis(new Vector(0, 0, 1), Math.PI/2);
			case Left:
				head.transform.orientation.makeRotationAxis(new Vector(0, 0, 1), Math.PI);
			default:
				head.transform.orientation.identity();
		}
		return orientation = v;
	}
}

private class Head {
	public var raw(default, null):Matrix;
	public var inverse(default, null):Matrix;
	public var transform(default, null):HeadTransform; // extra transform applied on head
	public var matrix(default, null):Matrix;
	public var azimuth(default, null):Float;
	public var elevation(default, null):Float;
	
	var vec = new Vector();
	
	public function new() {
		raw = new Matrix();
		matrix = new Matrix();
		inverse = new Matrix();
		transform = new HeadTransform();
		azimuth = elevation = 0;
	}
	
	public function refresh() {
		matrix.copy(transform.local).multiply(transform.orientation).multiply(raw).multiply(transform.global);
		// vec.set_xyz(0, 1, 0).applyProjection(matrix);
		// trace(vec.x, vec.y, vec.z);
		// if(vec.y < 0) {
		// 	matrix.multiply(new Matrix().makeRotationFromQuaternion(new Quaternion().betweenVectors(new Vector(0, -1, 0), vec.set_xyz(0, 0, -1).applyProjection(inverse.getInverse(matrix)))));
		// }


		inverse.getInverse(matrix);
		
		var te = inverse.elements;
		var m11 = te[0], m12 = te[4], m13 = te[8];
		var m21 = te[1], m22 = te[5], m23 = te[9];
		var m31 = te[2], m32 = te[6], m33 = te[10];
	
		elevation = Math.abs(m12) < 0.99999 ? Math.atan2(m32, m22) : Math.atan2(-m23, m33);
		azimuth = Math.abs(m23) < 0.99999 ? Math.atan2(m13, m33) : Math.atan2(-m31, m11);
	}
}

private class HeadTransform {
	public var global(default, null):Matrix; // in world coordinate
	public var orientation(default, null):Matrix; // in world coordinate
	public var local(default, null):Matrix; // in rawHead's coordinate
	
	public function new() {
		global = new Matrix();
		orientation = new Matrix();
		local = new Matrix();
	}
}

@:enum
abstract Orientation(Int) from Int {
	var Portrait = 0;
	var UpsideDown = 1;
	var Left = 2;
	var Right = 3;
}

class GvrRenderTarget implements RenderTarget {
    public var width: Int;
    public var height: Int;
    public var viewport_scale: Float;
    public var framebuffer: GLFramebuffer;
    public var renderbuffer: GLRenderbuffer;
	
	public function new(width, height) {
		this.width = width;
		this.height = height;
		viewport_scale = 1;
		framebuffer = new GLFramebuffer(0);
		renderbuffer = new GLRenderbuffer(0);
	}
}
class MonoRenderTarget implements RenderTarget {

	public var width: Int;
	public var height: Int;
	public var viewport_scale: Float;
	public var framebuffer: GLFramebuffer;
	public var renderbuffer: GLRenderbuffer;

	public function new(_render_w:Int, _render_h:Int, _render_scale:Float, _fb:GLFramebuffer, _rb:GLRenderbuffer) {
		width = _render_w;
		height = _render_h;
		viewport_scale = _render_scale;
		framebuffer = _fb;
		renderbuffer = _rb;
	}

}