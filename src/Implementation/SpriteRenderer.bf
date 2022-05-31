using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	[BonTarget,BonPolyRegister]
	struct SpriteState
	{
		public int layer = 0;
		public int frame; // TODO: separate system for ticking frame & animation...
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
			// TODO: render only what we see.

			for (let e in entities)
			{
				let spr = scene.GetComponent<SpriteState>(e);
				let tra = scene.GetComponent<Transform>(e);
				
				batch.SetLayer(spr.layer + (float)(tra.point.Y - cam.Bottom - (.)cam.Viewport.Y / 2) / cam.Viewport.Y);
				spr.sprite.Asset.Draw(batch, spr.frame, tra.point, tra.scale, tra.rotation);
			}
		}
	}
}
