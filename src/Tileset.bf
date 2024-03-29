using System;
using System.Collections;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	[BonTarget]
	struct TileCorner : IHashable
	{
		// 0 | 1
		// - + -
		// 2 | 3
		public Tile[4] tiles;

		public int GetHashCode()
		{
			return (int)tiles[0] + ((int)tiles[1] << 8) + ((int)tiles[2] << 16) + ((int)tiles[3] << 24);
		}
	}

	class Tileset
	{
		public struct TileSprite
		{
			public readonly Rect Clip;

			public this(Rect clip)
			{
				Clip = clip;
			}
		}

		public readonly UPoint2 TileSize;

		Frame[] frames ~ delete _;
		Dictionary<String, Animation> animations = new .() ~ delete _;

		// For a given tile configuration, get the number of variations
		Dictionary<TileCorner, uint8> variations = new .() ~ delete _;
		Dictionary<uint64, TileSprite> tiles = new .() ~ delete _;

		public this(Span<Frame> frameSpan, Span<TilesetEntry> tileSpan, Span<(String name, Animation anim)> animSpan, UPoint2 tileSize)
		{
			Debug.Assert(frameSpan.Length > 0, "Sprite has to have at least one frame");

			frames = new Frame[frameSpan.Length];
			if (frameSpan.Length > 0) frameSpan.CopyTo(frames);

			TileSize = tileSize;

			for (let entry in tileSpan)
			{
				// Update variation count
				uint8 startVariation = 0;
				if (variations.TryGetValue(entry.corner, let count))
				{
					variations[entry.corner] = count + entry.variations;
					startVariation = count;
				}
				else variations.Add(entry.corner, entry.variations);

				// Put combination in tiles lookup
				for (let i < entry.variations)
				{
					tiles.Add(((uint64)entry.corner.GetHashCode() + ((uint64)(startVariation + i) << 32)),
						TileSprite(Rect(i * (.)TileSize.X, @entry.Index * (.)TileSize.Y, (.)TileSize.X, (.)TileSize.Y)));
				}
			}

			for (let tup in animSpan)
				animations.Add(tup.name, tup.anim);
		}

		[Inline]
		public bool HasAnimation(String name) => animations.ContainsKey(name);

		[Inline]
		public bool HasTile(TileCorner corner, out uint8 variationCount) => variations.TryGetValue(corner, out variationCount);

		public Animation GetAnimation(String name)
		{
			if (animations.TryGetValue(name, let anim))
				return anim;

			Runtime.FatalError(scope $"Animation {name} couldn't be found");
		}

		[Inline]
		public void Draw(Batch2D batch, int frame, int variation, TileCorner corner, Vector2 position, Vector2 scale = .One, float rotation = 0, Color color = .White)
		{
#if DEBUG			
				Debug.Assert(variations.TryGetValue(corner, let variationCount));
				Debug.Assert(variationCount > variation);
#endif

			let tile = tiles[(uint64)corner.GetHashCode() + ((uint64)variation << 32)];
			batch.Image(frames[frame].Texture, tile.Clip, position, scale, .Zero, rotation, color);
		}
	}
}
