package luxe.gvr;

import cpp.*;
import gvr.c.*;
import snow.modules.opengl.GL;
import phoenix.RenderPath;
import luxe.gvr.GvrRenderPath;
import luxe.*;

class LuxeGvr {
	public var headMatrix:Matrix;
	public var headInverse:Matrix;
	public var mode(get, set):RenderMode;
	
	var cameras:Array<Camera>;
	var context:Context;
	var viewportList:BufferViewportList;
	var leftEyeViewport:BufferViewport;
	var rightEyeViewport:BufferViewport;
	var swapChain:SwapChain;
	var frame:Frame;
	var head:Mat4f;
	
	var monoTargetSize:Vector;
	var stereoTargetSize:Vector;
	var originalRenderPath:RenderPath;
	var originalCamera:Camera;
	var renderPath:GvrRenderPath;
	
	static var TO_RADIANS = Math.PI / 180;
	
	public function new() {
		monoTargetSize = Luxe.renderer.target_size.clone();
		stereoTargetSize = new Vector(Luxe.screen.width / 2, Luxe.screen.height);
		
		context = Gvr.create();
		Gvr.initializeGl(context);
		viewportList = Gvr.bufferViewportListCreate(context);
		leftEyeViewport = Gvr.bufferViewportCreate(context);
		rightEyeViewport = Gvr.bufferViewportCreate(context);
		swapChain = Gvr.swapChainCreate(context, 1);
		var size = Gvr.swapChainGetBufferSize(swapChain, 0);
		stereoTargetSize.x = size.width / 2;
		stereoTargetSize.y = size.height;
		Luxe.renderer.state.bindFramebuffer();
		Luxe.renderer.state.bindRenderbuffer();
		
		headMatrix = new Matrix();
		headInverse = new Matrix();
		
		originalCamera = Luxe.camera;
		Luxe.camera = new Camera({
			name: 'head',
			projection: phoenix.Camera.ProjectionType.perspective,
			fov: 90, near: 0.1, far: 1000,
			aspect: Luxe.screen.height / Luxe.screen.width,
		});
		Luxe.camera.view.cull_backfaces = false;
		
		cameras = [
			new Camera({
				name: 'left_eye',
				viewport: new Rectangle(0, 0, stereoTargetSize.x, stereoTargetSize.y),
				projection: custom,
			}),
			new Camera({
				name: 'right_eye',
				viewport: new Rectangle(stereoTargetSize.x, 0, stereoTargetSize.x, stereoTargetSize.y),
				projection: custom,
			}),
		];
		originalRenderPath = Luxe.renderer.render_path;
		Luxe.renderer.render_path = renderPath = new GvrRenderPath(Luxe.renderer, Luxe.camera, cameras[0], cameras[1]);
		
		Luxe.on(luxe.Ev.tickstart, ontickstart);
		Luxe.on(luxe.Ev.postrender, onpostrender);
	}
	
	function ontickstart(_) {	
		Gvr.getRecommendedBufferViewports(context, viewportList);
		Gvr.bufferViewportListGetItem(viewportList, 0, leftEyeViewport);
		Gvr.bufferViewportListGetItem(viewportList, 1, rightEyeViewport);
		var time = Gvr.getTimePointNow();
		head = Gvr.getHeadSpaceFromStartSpaceRotation(context, time);
		
		mat4fToMatrix(head, headMatrix);
		headInverse.getInverse(headMatrix);
		
		if(mode == Stereo) {
			var leftEye = Gvr.getEyeFromHeadMatrix(context, 0);
			var rightEye = Gvr.getEyeFromHeadMatrix(context, 1);
			var leftEyeMatrix = mat4fToMatrix(leftEye).multiply(headMatrix);
			var rightEyeMatrix = mat4fToMatrix(rightEye).multiply(headMatrix);
			
			cameras[0].rotation.setFromRotationMatrix(leftEyeMatrix.inverse());
			cameras[0].pos.set_xyz(0, 0, 0).applyProjection(leftEyeMatrix);
			cameras[1].rotation.setFromRotationMatrix(rightEyeMatrix.inverse());
			cameras[1].pos.set_xyz(0, 0, 0).applyProjection(rightEyeMatrix);
			
			cameras[0].view.projection_matrix = perspective(Gvr.bufferViewportGetSourceFov(leftEyeViewport), 0.1, 100);
			cameras[0].view.proj_arr = cameras[0].view.projection_matrix.float32array();
			cameras[1].view.projection_matrix = perspective(Gvr.bufferViewportGetSourceFov(rightEyeViewport), 0.1, 100);
			cameras[1].view.proj_arr = cameras[1].view.projection_matrix.float32array();
			
			frame = Gvr.swapChainAcquireFrame(swapChain);
			Gvr.frameBindBuffer(frame, 0);
			Luxe.renderer.state.enable(GL.DEPTH_TEST);
		} else {
			Luxe.camera.rotation.setFromRotationMatrix(headInverse);
		}
		
		Luxe.renderer.blend_mode(src_alpha, one_minus_src_alpha);
	}
	
	function onpostrender(_) {
		if(mode == Stereo) {
			Gvr.frameUnbind(frame);
			Gvr.frameSubmit(frame, viewportList, head);
			
			Luxe.renderer.state.bindFramebuffer();
			Luxe.renderer.state.bindRenderbuffer();
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
		Luxe.renderer.target_size.copy_from(monoTargetSize);
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
		Luxe.renderer.target_size = switch v {
			case Mono: monoTargetSize;
			case Stereo: stereoTargetSize;
		}
		return renderPath.mode = v;
	}
}