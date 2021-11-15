using System;
using System.Diagnostics;
using Pile;
using Atma;

namespace Dimtoo
{
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

		public void Render(Batch2D batch)
		{
			// TODO: render only what we see. same goes for tiles

			for (let e in entities)
			{
				let spr = componentManager.GetComponent<SpriteRenderer>(e);
				let tra = componentManager.GetComponent<Transform>(e);

				spr.sprite.Asset.Draw(batch, spr.frame, tra.position.Round(), tra.scale, tra.rotation);
			}
		}
	}
}
