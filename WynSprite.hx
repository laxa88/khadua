package wyn;

import kha.Color;
import kha.Image;
import kha.Rectangle;
import kha.Loader;
import kha.math.FastMatrix3;
import kha.math.FastVector2;
import kha.graphics2.Graphics;
import kha.graphics2.GraphicsExtension;

typedef SliceData = {
	var x:Int; // the position and size of the button image to be 9-sliced
	var y:Int;
	var width:Int;
	var height:Int;
	var borderLeft:Int; // the 9-slice offset to cut from. It's the same as how Unity's SpriteEditor does it.
	var borderTop:Int;
	var borderRight:Int;
	var borderBottom:Int;
}

class WynSprite extends WynObject
{
	/**
	 * This is the base class for anything that can be rendered,
	 * such as sprites, texts, bitmaptexts, buttons, etc.
	 */

	public static var LEFT:Int 		= 0;
	public static var RIGHT:Int 	= 1;
	public static var UP:Int 		= 2;
	public static var DOWN:Int 		= 3;

	public static var SINGLE:Int 			 = 0;
	public static var SINGLE9SLICE:Int 		 = 0;
	public static var BUTTON:Int 			 = 0;
	public static var BUTTON9SLICE:Int 		 = 0;

	public var animator:WynAnimator; // Controls all animations
	public var image:Image;
	public var frameColumns:Int = 0; // Number of columns in spritesheet
	public var frameX:Int = 0; // Frame position, for animation purpose
	public var frameY:Int = 0;
	public var frameWidth:Int = 0; // Individual frame's size
	public var frameHeight:Int = 0;
	public var offset:FastVector2 = new FastVector2();
	public var color:Color = Color.White; // tint, default is white
	public var alpha:Float = 1.0; // Opacity - 0.0 to 1.0
	public var scale:Float = 1.0;
	public var flipX:Bool = false;
	public var flipY:Bool = false;
	public var facing(default, set):Int;
	var _faceMap:Map<Int, {x:Bool, y:Bool}> = new Map<Int, {x:Bool, y:Bool}>();
	var _spriteType:Int;

	// NOTE:
	// "image" is used for the usual rendering
	// "originalImage" is used for storing full button spritesheet image,
	// which will be re-9-sliced everytime the width or height changes.
	var originalImage:Image;
	var sliceData:SliceData;



	public function new (x:Float=0, y:Float=0, w:Float=0, h:Float=0)
	{
		super(x, y, w, h);

		// By default
		_spriteType = SINGLE;

		animator = new WynAnimator(this);
	}

	override public function update (dt:Float)
	{
		super.update(dt);

		// update animation
		animator.update(dt);

		// update frame index
		updateAnimator();
	}

	override public function render (c:WynCamera)
	{
		super.render(c);

		var g = c.buffer.g2;

		// Get the position in relation to camera's scroll position
		var ox = x - c.scrollX - c.shakeX;
		var oy = y - c.scrollY - c.shakeY;

		// Rather than rendering onto the final buffer directly, we
		// render into each available camera, and offset based on the
		// camera's scrollX/scrollY. The cameras' images are then
		// rendered onto the final buffer.

		if (Wyngine.DEBUG_DRAW && Wyngine.DRAW_COUNT < Wyngine.DRAW_COUNT_MAX)
		{
			g.color = Color.Green;
			g.drawRect(ox, oy, frameWidth, frameHeight);

			Wyngine.DRAW_COUNT++;
		}

		if (image != null && visible)
		{
			g.color = color;

			// If an image is flipped, we need to offset it by width/height
			var fx = (flipX) ? -1 : 1; // flip image?
			var fy = (flipY) ? -1 : 1;
			var dx = (flipX) ? frameWidth : 0; // if image is flipped, displace
			var dy = (flipY) ? frameHeight : 0;

			// Remember: Rotations are expensive!
			if (angle != 0)
			{
				var rad = WynUtil.degToRad(angle);
				g.pushTransformation(g.transformation
					// offset toward top-left, to center image on pivot point
					.multmat(FastMatrix3.translation(ox + frameWidth/2, oy + frameHeight/2))
					// rotate at pivot point
					.multmat(FastMatrix3.rotation(rad))
					// reverse offset
					.multmat(FastMatrix3.translation(-ox - frameWidth/2, -oy - frameHeight/2)));
			}

			// Add opacity if any
			if (alpha != 1) g.pushOpacity(alpha);

			// Draw the actual image
			// TODO: scale?
			g.drawScaledSubImage(image,
				// the spritesheet's frame to extract from
				frameX, frameY, frameWidth, frameHeight, 
				// the target position
				ox + (dx+frameWidth/2) - (frameWidth/2),
				oy + (dy+frameHeight/2) - (frameHeight/2),
				frameWidth * fx * scale,
				frameHeight * fy * scale);

			// Finalise opacity
			if (alpha != 1) g.popOpacity();

			// Finalise the rotation
			if (angle != 0) g.popTransformation();
		}

		if (Wyngine.DEBUG_DRAW && Wyngine.DRAW_COUNT < Wyngine.DRAW_COUNT_MAX)
		{
			// Debug hitbox
			g.color = Color.Red;
			g.drawRect(ox + offset.x, oy + offset.y, width, height);

			Wyngine.DRAW_COUNT++;
		}
	}

	override public function destroy ()
	{
		super.destroy();
	}

	/**
	 * This flags the object for pooling.
	 */
	override public function kill ()
	{
		super.kill();

		// NOTE: we don't set these by default because
		// use cases are diverse. E.g. When a character dies,
		// he is still active and visible (updates and renders),
		// but will not do some "alive" logic.

		// active = false;
		// visible = false;
	}

	/**
	 * This flags the object for pooling.
	 */
	override public function revive ()
	{
		super.revive();

		// NOTE: Similar comments to kill() above

		// active = true;
		// visible = true;
	}

	/**
	 * When you don't need fancy quadtrees, you can
	 * use this for single checks.
	 */
	override public function collide (other:WynObject) : Bool
	{
		var hitHoriz:Bool;
		var hitVert:Bool;
		var otherx:Float;
		var othery:Float;

		if (Std.is(other, WynSprite))
		{
			var sprite = cast (other, WynSprite);
			otherx = sprite.x + sprite.offset.x;
			othery = sprite.y + sprite.offset.y;
		}
		else
		{
			otherx = other.x;
			othery = other.y;
		}

		if (x < otherx)
			hitHoriz = otherx < (x + width);
		else
			hitHoriz = x < (otherx + other.width);

		if (y < othery)
			hitVert = othery < (y + height);
		else
			hitVert = y < (othery + other.height);

		return (hitHoriz && hitVert);
	}



	/**
	 * Convenient method to create images if you're prototyping without images.
	 */
	public function createEmptyImage (w:Int=50, h:Int=50)
	{
		// Reset the size
		width = w;
		height = h;

		// Create a new image
		image = Image.createRenderTarget(w, h);

		// Set the frame size to same as image size
		frameWidth = w;
		frameHeight = h;

		// NOTE: does not adjust hitbox offset
	}

	/**
	 * Convenient method to create images if you're prototyping without images.
	 */
	public function createPlaceholderRect (color:Color, w:Int=50, h:Int=50, filled:Bool=false)
	{
		createEmptyImage(w, h);

		image.g2.begin(true, Color.fromValue(0x00000000));
		image.g2.color = color;
		if (filled)
			image.g2.fillRect(0, 0, w, h);
		else
			image.g2.drawRect(0, 0, w, h);
		image.g2.end();
	}

	/**
	 * Convenient method to create images if you're prototyping without images.
	 */
	public function createPlaceholderCircle (color:Color, radius:Int=25, filled:Bool=false)
	{
		createEmptyImage(radius*2, radius*2);

		image.g2.begin(true, Color.fromValue(0x00000000));
		image.g2.color = color;
		if (filled)
			GraphicsExtension.fillCircle(image.g2, radius, radius, radius);
		else
			GraphicsExtension.drawCircle(image.g2, radius, radius, radius);
		image.g2.end();
	}

	/**
	 * Load image via kha's internal image loader. Make
	 * sure you loaded the room that contains this image,
	 * in project.kha.
	 */
	public function loadImage (name:String, frameW:Int, frameH:Int)
	{
		// Image name is set from project.kha
		image = Loader.the.getImage(name);

		// Update variables
		frameWidth = frameW;
		frameHeight = frameH;
		frameX = 0;
		frameY = 0;
		frameColumns = Std.int(image.width / frameWidth);

		// This is the hitbox, not the image size itself.
		// Use scale to resize the image, then remember to
		// adjust the hitbox after scaling.
		width = frameW;
		height = frameH;

		// NOTE: does not adjust hitbox offset
	}

	public function load9SliceImage (name:String, ?data:SliceData)
	{
		// This is the original image which we'll use as a base for 9-slicing.
		originalImage = Loader.the.getImage(name);

		var w:Int = cast width;
		var h:Int = cast height;

		// The target image is the size as defined in new()
		image = Image.createRenderTarget(w, h);

		// Update the frame, otherwise it won't appear.
		frameWidth = w;
		frameHeight = h;

		if (data != null)
		{
			// Draw the slice directly onto the image, if there's
			// the slice data. Otherwise, we're gonna just draw the whole
			// original image and scale it.
			sliceData = data;
			drawSlice(originalImage, image, data);
		}
		else
		{
			// If no slice data is given, then we'll scale and fit the whole
			// originalImage onto the final image.
			image.g2.begin();
			image.g2.drawScaledImage(originalImage, 0, 0, image.width, image.height);
			image.g2.end();
		}
	}

	/**
	 * Draw each section of the 9-slice based on the data
	 */
	function drawSlice (source:Image, target:Image, data:WynSprite.SliceData)
	{
		var g:Graphics = target.g2;

		// If the total of 3-slices horizontally or vertically
		// is longer than the actual button's size, Then we'll have
		// to scale the borders so that they'll stay intact.
		var ratioW = 1.0;
		var ratioH = 1.0;

		// Get the border width and height (without the corners)
		var sw = data.width - data.borderLeft - data.borderRight;
		var sh = data.height - data.borderTop - data.borderBottom;
		var dw = width - data.borderLeft - data.borderRight;
		var dh = height - data.borderTop - data.borderBottom;
		// Width and height cannot be less than zero.
		if (sw < 0) sw = 0;
		if (sh < 0) sh = 0;
		if (dw < 0) dw = 0;
		if (dh < 0) dh = 0;

		// Get ratio of the border corners if the width or height
		// is zero or less. Imagine when a 9-slice image is too short,
		// we end up not seeing the side borders anymore; only the corners.
		// When that happens, we have to scale the corners by ratio.
		if (width < data.borderLeft + data.borderRight)
			ratioW = width / (data.borderLeft + data.borderRight);

		if (height < data.borderTop + data.borderBottom)
			ratioH = height / (data.borderTop + data.borderBottom);

		// begin drawing
		g.begin();

		// top-left border
		g.drawScaledSubImage(source,
			0, 0, data.borderLeft, data.borderTop, // source
			0, 0, data.borderLeft*ratioW, data.borderTop*ratioH // destination
			);

		// top border
		g.drawScaledSubImage(source,
			data.borderLeft, 0, sw, data.borderTop,
			data.borderLeft*ratioW, 0, dw, data.borderTop*ratioH
			);

		// top-right border
		g.drawScaledSubImage(source,
			data.width-data.borderRight, 0, data.borderRight, data.borderTop,
			width-data.borderRight*ratioW, 0, data.borderRight*ratioW, data.borderTop*ratioH
			);

		// middle-left border
		g.drawScaledSubImage(source,
			0, data.borderTop, data.borderLeft, sh,
			0, data.borderTop*ratioH, data.borderLeft*ratioW, dh
			);

		// middle
		g.drawScaledSubImage(source,
			data.borderLeft, data.borderTop, sw, sh,
			data.borderLeft*ratioW, data.borderTop*ratioH, dw, dh
			);

		// middle-right border
		g.drawScaledSubImage(source,
			data.width-data.borderRight, data.borderTop, data.borderRight, sh,
			width-data.borderRight*ratioW, data.borderTop*ratioH, data.borderRight*ratioW, dh
			);

		// bottom-left border
		g.drawScaledSubImage(source,
			0, data.height-data.borderBottom, data.borderLeft, data.borderBottom,
			0, height-data.borderBottom*ratioH, data.borderLeft*ratioW, data.borderBottom*ratioH
			);

		// bottom
		g.drawScaledSubImage(source,
			data.borderLeft, data.height-data.borderBottom, sw, data.borderBottom,
			data.borderLeft*ratioW, height-data.borderBottom*ratioH, dw, data.borderBottom*ratioH
			);

		// bottom-right border
		g.drawScaledSubImage(source,
			data.width-data.borderRight, data.height-data.borderBottom, data.borderRight, data.borderBottom,
			width-data.borderRight*ratioW, height-data.borderBottom*ratioH, data.borderRight*ratioW, data.borderBottom*ratioH
			);

		g.end();
	}

	/**
	 * Not sure if this will not work on an existing image
	 * because in Khasteroids, the image width/height do not reset.
	 * NOTE: doing this does not reset the animation
	 * and frame x/y/width/height values, remember to
	 * manually update them.
	 */
	public function setImage (img:Image)
	{
		image = img;

		// NOTE: does not adjust hitbox offset
	}

	public function playAnim (name:String, reset:Bool=false)
	{
		animator.play(name, reset);

		// update the sheet
		updateAnimator();
	}

	function updateAnimator ()
	{
		var sheetIndex:Int = animator.getSheetIndex();
		frameX = Std.int(sheetIndex % frameColumns) * frameWidth;
		frameY = Std.int(sheetIndex / frameColumns) * frameHeight;
	}

	/**
	 * Maps a direction to whether the image should flip on X/Y axis.
	 * E.g.
	 * setFaceFlip(WynObject.UP, false, true); // sets to flip on Y-axis if this sprite's direction is UP
	 * setFaceFlip(WynObject.LEFT, true, false); // sets to flip on X-axis if this sprite's direction is LEFT
	 */
	public function setFaceFlip (direction:Int, flipX:Bool, flipY:Bool)
	{
		_faceMap.set(direction, {x:flipX, y:flipY});
	}

	public function setHitbox (x:Float, y:Float, w:Float, h:Float)
	{
		offset.x = x;
		offset.y = y;
		width = w;
		height = h;
	}



	/**
	 * This applies X/Y flip based on what you set from
	 * setFaceFlip() method. If map is not set, nothing happens.
	 */
	private function set_facing (direction:Int) : Int
	{
		var flip = _faceMap.get(direction);
		if (flip != null)
		{
			flipX = flip.x;
			flipY = flip.y;
		}
		
		return (facing = direction);
	}

	override private function set_width (val:Float) : Float
	{
		width = val;

		// Every time we change the size, update the 9-slice
		if (_spriteType == SINGLE9SLICE ||
			_spriteType == BUTTON9SLICE)
		{
			// Resize the target images
			var w = cast width;
			var h = cast height;
			// image = Image.createRenderTarget(w, h);

			if (sliceData != null)
				drawSlice(originalImage, image, sliceData);
		}

		return width;
	}

	override private function set_height (val:Float) : Float
	{
		height = val;

		if (_spriteType == SINGLE9SLICE ||
			_spriteType == BUTTON9SLICE)
		{
			// Resize the target images
			var w = cast width;
			var h = cast height;
			// image = Image.createRenderTarget(w, h);

			if (sliceData != null)
				drawSlice(originalImage, image, sliceData);
		}

		return height;
	}
}