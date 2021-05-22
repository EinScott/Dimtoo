using Pile;
using System.Diagnostics;

namespace Dimtoo
{
	[Render]
	class SpriteRenderer : Component
	{
		Asset<Sprite> Asset;
		bool deleteAsset;
		Transform transform;

		public int frame;
		public Color color = .White;

		public this(Asset<Sprite> asset, bool ownsAsset = false)
		{
			Asset = asset;
			deleteAsset = ownsAsset;
		}

		public ~this()
		{
			if (deleteAsset)
				delete Asset;
		}

		protected override void Attach()
		{
			transform = Entity.GetComponent<Transform>();
		}

		protected override void Render(Batch2D batch)
		{
			Debug.Assert(Asset != null, "Provide SpriteRenderer with Asset before rendering");
			Asset.Asset.Draw(batch, frame, transform.Position.Round(), transform.Scale, transform.Rotation, color);
		}
	}
}
