using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	[BonTarget,BonPolyRegister]
	struct SpriteState
	{
		public int16 layer = 0;
		public Point2 drawOffset = default;
		public int frame;
		public int frameTicks = 0;
		public int state = 0;
		public int nextState = 0;
		public bool queueNextState = false;
		public Asset<Sprite> sprite;

		public this(Asset<Sprite> sprite, int frame = 0)
		{
			Debug.Assert(frame >= 0);
			this.sprite = sprite;
			this.frame = frame;
		}
	}

	class SpriteRendererSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(SpriteState), typeof(Transform));
		this
		{
			signatureTypes = wantsComponents;
		}

		public Camera2D cam;

		public float GetRenderLayer()
		{
			return 0;
		}

		[PerfTrack]
		public void Render(Batch2D batch)
		{
			for (let e in entities)
			{
				let spr = scene.GetComponent<SpriteState>(e);
				let tra = scene.GetComponent<Transform>(e);

				// TODO does not take into consideration scaled or rotated sprites...

				let sprite = spr.sprite.Asset;
				var localBounds = sprite?.Bounds ?? .SizeOne;
				localBounds.Position += tra.point;
				if (!cam.CameraRect.Overlaps(localBounds))
					continue;

				let depth = (float)(tra.point.Y - cam.Bottom - (float)cam.Viewport.Y / 2) / cam.Viewport.Y;
				batch.SetLayer((float)spr.layer + depth);

				if (sprite == null)
				{
					batch.Rect(tra.point + spr.drawOffset - .(16), .(32), .White);
					continue;
				}

				if (sprite.Animations.Length > 0)
				{
					spr.frameTicks++;
					let durationTicks = SecondsToTicks!((float)sprite.Frames[spr.frame].Duration / 1000);
					while (spr.frameTicks > durationTicks)
					{
						spr.frameTicks -= durationTicks;

						if (sprite.Animations[spr.state].To <= spr.frame)
						{
							if (spr.queueNextState)
							{
								Debug.Assert(spr.nextState < sprite.Animations.Length);
								spr.state = spr.nextState;
								spr.queueNextState = false;
							}

							spr.frame = sprite.Animations[spr.state].From;
						}
						else spr.frame++;
					}
				}

				sprite.Draw(batch, spr.frame, tra.point + spr.drawOffset, tra.scale, tra.rotation);
			}
		}
	}
}
