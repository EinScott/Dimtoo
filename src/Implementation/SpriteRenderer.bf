using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	[BonTarget,BonPolyRegister]
	struct SpriteRenderer
	{
		public int frame;
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
		static Type[?] wantsComponents = .(typeof(SpriteRenderer), typeof(Transform));
		this
		{
			signatureTypes = wantsComponents;
		}

		public int GetRenderLayer()
		{
			return 0;
		}

		[PerfTrack]
		public void Render(Batch2D batch)
		{
			// TODO: render only what we see. same goes for tiles

			for (let e in entities)
			{
				let spr = scene.GetComponent<SpriteRenderer>(e);
				let tra = scene.GetComponent<Transform>(e);

				spr.sprite.Asset.Draw(batch, spr.frame, tra.point, tra.scale, tra.rotation);
			}
		}
	}
}
