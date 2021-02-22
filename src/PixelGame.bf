using Pile;
using System;

namespace Dimtoo
{
	class PixelGame<T> : Game<T> where T : Game
	{
		public enum ScalingMode
		{
			PixelPerfect,
			FillWindow,
			FitFrame
		}

		public readonly UPoint2 FrameSize;
		[Inline]
		public FrameBuffer Frame => frame;
		public ScalingMode Scaling = .PixelPerfect;

		FrameBuffer frame ~ delete _;
		float renderScale;
		Point2 frameOffset;

		public this(UPoint2 size) : base()
		{
			FrameSize = size;
		}

		void Resized()
		{
			switch (Scaling)
			{
			case .PixelPerfect:
				// Update render scale to biggest pixel perfect match
				renderScale = (uint)Math.Max(Math.Min(
				        Math.Floor(Core.Window.RenderSize.X / (float)frame.RenderSize.X),
				        Math.Floor(Core.Window.RenderSize.Y / (float)frame.RenderSize.Y)), 1);

				// Update frame offset to be centered
				frameOffset = Point2(
				    (int)((Core.Window.RenderSize.X - renderScale * frame.RenderSize.X) / 2),
				    (int)((Core.Window.RenderSize.Y - renderScale * frame.RenderSize.Y) / 2));
			case .FitFrame:
				Core.FatalError("Not implemented"); // TODO non perfect pixel scaling
			case .FillWindow:
				Core.FatalError("Not implemented"); // TODO non perfect pixel scaling
			}
		}

		protected override void Startup()
		{
			frame = new FrameBuffer((.)FrameSize.X, (.)FrameSize.Y, .Color);

			//Core.Window.Resizable = true; (i guess you should still decide this yourself)
			Core.Window.OnResized.Add(new => Resized);
			Core.Window.MinSize = FrameSize;
			Resized();
		}

		protected void RenderFrame(Batch2D batch)
		{
			batch.Image(frame, frameOffset, Vector2(renderScale, renderScale), .Zero, 0, .White);
		}

		public Point2 WindowToFrame(Point2 windowPosition)
		{
			var windowPosition;

		    // Take into account Frame to Window Origin offset
		    windowPosition -= frameOffset;

		    // Make position relative to frame buffer origin
		    let framePos = (Vector2)windowPosition / renderScale;

		    return framePos.Round();
		}
	}
}
