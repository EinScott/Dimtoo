using System;
using System.Collections;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	class Sprite
	{
		Frame[] frames ~ delete _;
		Animation[] animations ~ delete _;
		Dictionary<String,int> animNameMap ~ DeleteDictionaryAndKeys!(_);

		public readonly Rect Bounds => {
			let subt = frames[0].Texture;
			var bounds = subt.Frame;
			bounds.Position -= Origin;
			bounds
		};
		public readonly Point2 Origin;

		public readonly ReadOnlySpan<Frame> Frames;
		public readonly ReadOnlySpan<Animation> Animations;

		public this(Span<Frame> frameSpan, Span<(String name, Animation anim)> animSpan, Point2 origin = .Zero)
		{
			Debug.Assert(frameSpan.Length > 0, "Sprite has to have at least one frame");

			frames = new Frame[frameSpan.Length];
			if (frameSpan.Length > 0) frameSpan.CopyTo(frames);

			animations = new .[animSpan.Length];
			animNameMap = new .((.)animSpan.Length);
			for (let tup in animSpan)
			{
				animations[@tup.Index] = tup.anim;
				animNameMap.Add(tup.name, @tup.Index);
			}

			Frames = frames;
			Origin = origin;

			Animations = animations;
			Frames = frames;
		}

		[Inline]
		public bool HasAnimation(String name) => animNameMap.ContainsKey(name);

		public Animation GetAnimation(String name)
		{
			if (animNameMap.TryGetValue(name, let animIdx))
				return animations[animIdx];

			Runtime.FatalError(scope $"Animation {name} couldn't be found");
		}

		public int GetAnimationIndex(String name)
		{
			if (animNameMap.TryGetValue(name, let animIdx))
				return animIdx;

			return -1;
		}

		[Inline]
		public void Draw(Batch2D batch, int frame, Vector2 position, Vector2 scale = .One, float rotation = 0, Color color = .White)
		{
			batch.Image(frames[frame].Texture, position, scale, Origin , rotation, color);
		}

		public static operator Subtexture(Sprite spr) => spr.frames[0].Texture;
	}
}
