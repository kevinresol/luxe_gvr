package luxe.gvr;

import luxe.Camera;
import luxe.Events;
import phoenix.RenderPath;
import phoenix.Batcher;
import phoenix.Renderer;

class GvrRenderPath extends phoenix.RenderPath {
	
	var head:Camera;
	var leftEye:Camera;
	var rightEye:Camera;
	
	var mode:RenderMode = Stereo;
	
    public function new( _renderer:Renderer, head, left, right ) {
        super(_renderer);
		this.head = head;
		leftEye = left;
		rightEye = right;
    }

    override function render( _batchers: Array<Batcher>, _stats:RendererStats ) {

		var mono = mode == Mono;
		
        for(batcher in _batchers) {
            if(batcher.enabled) {

				if(mono) {
					Luxe.events.fire('gvr.onrender.mono');
					batcher.view = head.view;
					batcher.draw();
				} else {
					Luxe.events.fire('gvr.onrender.stereo.left');
					batcher.view = leftEye.view;
					batcher.draw();
					Luxe.events.fire('gvr.onrender.stereo.right');
					batcher.view = rightEye.view;
					batcher.draw();
				}

            } //batcher enabled
        } //each batcher

    } //render
}

enum RenderMode {
	Mono;
	Stereo;
}