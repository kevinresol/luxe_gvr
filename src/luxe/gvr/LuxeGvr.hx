package luxe.gvr;

import cpp.*;
import gvr.c.*;
import phoenix.RenderPath;
import luxe.*;

class LuxeGvr {
	public var headMatrix:Matrix;
	public var headInverse:Matrix;
	
	var cameras:Array<Camera>;
	var context:Context;
	var viewportList:BufferViewportList;
	var leftEyeViewport:BufferViewport;
	var rightEyeViewport:BufferViewport;
	var swapChain:SwapChain;
	var frame:Frame;
	var head:Mat4f;
	
	var originalTargetSize:Vector;
	var originalRenderPath:RenderPath;
	
	public function new() {
		var viewportSize = {
			w: Luxe.screen.width / 2,
			h: Luxe.screen.h,
		}
		
		context = Gvr.create();
		Gvr.initializeGl(context);
		viewportList = Gvr.bufferViewportListCreate(context);
		leftEyeViewport = Gvr.bufferViewportCreate(context);
		rightEyeViewport = Gvr.bufferViewportCreate(context);
		swapChain = Gvr.swapChainCreate(context, 1);
		var size = Gvr.swapChainGetBufferSize(swapChain, 0);
		viewportSize.w = size.width / 2;
		viewportSize.h = size.height;
		trace(viewportSize);
		Luxe.renderer.state.bindFramebuffer();
		Luxe.renderer.state.bindRenderbuffer();
		
		headMatrix = new Matrix();
		headInverse = new Matrix();
		
		cameras = [
			// Luxe.camera,
			new Camera({
				name: 'left_eye',
				viewport: new Rectangle(0, 0, viewportSize.w, viewportSize.h),
				projection: custom,
			}),
			new Camera({
				name: 'right_eye',
				viewport: new Rectangle(viewportSize.w, 0, viewportSize.w, viewportSize.h),
				projection: custom,
				// projection: perspective,
				// fov: 90,
				// far: 1000, near: -0,
				// aspect: 1,
			}),
		];
		originalRenderPath = Luxe.renderer.render_path;
		originalTargetSize = Luxe.renderer.target_size.clone();
		Luxe.renderer.render_path = new VrRenderPath(Luxe.renderer, cameras);
		Luxe.renderer.target_size.y = viewportSize.h;
		
		Luxe.on(luxe.Ev.tickstart, ontickstart);
		Luxe.on(luxe.Ev.postrender, onpostrender);
	}
	
	function ontickstart(_) {	
		Gvr.getRecommendedBufferViewports(context, viewportList);
		Gvr.bufferViewportListGetItem(viewportList, 0, leftEyeViewport);
		Gvr.bufferViewportListGetItem(viewportList, 1, rightEyeViewport);
		frame = Gvr.swapChainAcquireFrame(swapChain);
		var time = Gvr.getTimePointNow();
		head = Gvr.getHeadSpaceFromStartSpaceRotation(context, time);
		var leftEye = Gvr.getEyeFromHeadMatrix(context, 0);
		var rightEye = Gvr.getEyeFromHeadMatrix(context, 1);
		
		mat4fToMatrix(head, headMatrix);
		headInverse.getInverse(headMatrix);
		var leftEyeMatrix = mat4fToMatrix(leftEye).multiply(headMatrix);
		var rightEyeMatrix = mat4fToMatrix(rightEye).multiply(headMatrix);
		
		cameras[0].rotation.setFromRotationMatrix(leftEyeMatrix.inverse());
		cameras[0].pos = new Vector().applyProjection(leftEyeMatrix);
		cameras[1].rotation.setFromRotationMatrix(rightEyeMatrix.inverse());
		cameras[1].pos = new Vector().applyProjection(rightEyeMatrix);
		
		cameras[0].view.projection_matrix = perspective(Gvr.bufferViewportGetSourceFov(leftEyeViewport), 0.1, 100);
		cameras[0].view.proj_arr = cameras[0].view.projection_matrix.float32array();
		cameras[1].view.projection_matrix = perspective(Gvr.bufferViewportGetSourceFov(rightEyeViewport), 0.1, 100);
		cameras[1].view.proj_arr = cameras[1].view.projection_matrix.float32array();
		
		Gvr.frameBindBuffer(frame, 0);
		opengl.WebGL.enable(opengl.GL.GL_DEPTH_TEST);
		
		Luxe.renderer.blend_mode(src_alpha, one_minus_src_alpha);
	}
	
	function onpostrender(_) {
		Gvr.frameUnbind(frame);
		Gvr.frameSubmit(frame, viewportList, head);
		
		Luxe.renderer.state.bindFramebuffer();
		Luxe.renderer.state.bindRenderbuffer();
	}
	
	public function destroy() {
		// TODO
		// Gvr.destroy(RawPointer.addressOf(context.raw));
		// context = null;
		
		Luxe.off(luxe.Ev.tickstart, ontickstart);
		Luxe.off(luxe.Ev.postrender, onpostrender);
		Luxe.renderer.render_path = originalRenderPath;
		Luxe.renderer.target_size.copy_from(originalTargetSize);
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

		var x_left = -Math.tan(fov.left * Math.PI / 180.0) * z_near;
		var x_right = Math.tan(fov.right * Math.PI / 180.0) * z_near;
		var y_bottom = -Math.tan(fov.bottom * Math.PI / 180.0) * z_near;
		var y_top = Math.tan(fov.top * Math.PI / 180.0) * z_near;
		
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
}