using System;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	public class Sprite
	{
		public class Animation
		{
			public readonly String Name = new String() ~ delete _;
			public readonly int From;
			public readonly int To;

			public this(StringView name, int from, int to)
			{
				Name.Set(name);
				From = from;
				To = to;
			}
		}

		public class Frame
		{
			public readonly Subtexture Texture;
			public readonly int Duration;

			public this(Subtexture texture, int duration)
			{
				Texture = texture;
				Duration = duration;
			}

			public static operator Subtexture(Frame frame) => frame.Texture;
		}

		Frame[] frames ~ DeleteContainerAndItems!(_);
		Animation[] animations ~ DeleteContainerAndItems!(_);
		
		public readonly Point2 Origin;

		public readonly ReadOnlySpan<Frame> Frames;
		public readonly ReadOnlySpan<Animation> Animations;

		public this(Span<Frame> frameSpan, Span<Animation> animSpan, Point2 origin = .Zero)
		{
			Debug.Assert(frameSpan.Length > 0, "Sprite has to have at least one frame");

			frames = new Frame[frameSpan.Length];
			if (frameSpan.Length > 0) frameSpan.CopyTo(frames);

			animations = new Animation[animSpan.Length];
			if (animSpan.Length > 0) animSpan.CopyTo(animations);

			Frames = frames;
			Animations = animations;
			Origin = origin;
		}

		public Animation GetAnimation(String name)
		{
			for (let anim in animations)
				if (name == anim.Name) return anim;

			Log.Warn(scope $"Animation {name} couldn't be found");
			return null;
		}

		public void Draw(Batch2D batch, int frame, Vector2 position, Vector2 scale = .One, float rotation = 0, Color color = .White)
		{
			batch.Image(frames[frame].Texture, position, scale, Origin , rotation, color);
		}

		public static operator Subtexture(Sprite spr) => spr.frames[0].Texture;
	}
}
