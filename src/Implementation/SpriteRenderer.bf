using System;
using Pile;

namespace Dimtoo
{
	struct SpriteRenderer
	{
		public int frame;
		public Asset<Sprite> sprite;
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
			for (let e in entities)
			{
				let spr = componentManager.GetComponent<SpriteRenderer>(e);
				let tra = componentManager.GetComponent<Transform>(e);

				spr.sprite.Asset.Draw(batch, spr.frame, tra.position.Round(), tra.scale, tra.rotation);
			}
		}
	}
}
