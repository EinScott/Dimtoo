using System;
using System.Collections;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	enum TileCorner : uint8
	{
		None,

		TopLeft = 1,
		TopRight = 1 << 1,
		BottomLeft = 1 << 2,
		BottomRight = 1 << 3,

		LeftSide = TopLeft | BottomLeft,
		RightSide = TopRight | BottomRight,

		DownSide = BottomLeft | BottomRight,
		UpSide = TopLeft | TopRight,

		All = LeftSide | RightSide
	}

	class Tileset
	{
		public struct Tile
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

		// The key here is connection + (variation << 8)
		Dictionary<uint16, Tile> tiles = new .() ~ delete _;

		public this(Span<Frame> frameSpan, Span<(TileCorner corner, UPoint2 tileOffset)> tileSpan, Span<(String name, Animation anim)> animSpan, UPoint2 tileSize)
		{
			Debug.Assert(frameSpan.Length > 0, "Sprite has to have at least one frame");

			frames = new Frame[frameSpan.Length];
			if (frameSpan.Length > 0) frameSpan.CopyTo(frames);

			TileSize = tileSize;

			for (let tup in tileSpan)
			{
				// Update variation count
				uint8 variation = 0;
				if (variations.TryGetValue(tup.corner, let val))
					variation = variations[tup.corner] = val + 1;
				else variations.Add(tup.corner, 1);

				// Put combination in tiles lookup
				tiles.Add(((uint16)tup.corner + ((uint16)variation << 8)),
					Tile(Rect(tup.tileOffset, TileSize)));
			}

			for (let tup in animSpan)
				animations.Add(tup.name, tup.anim);
		}

		[Inline]
		public bool HasAnimation(String name) => animations.ContainsKey(name);

		[Inline]
		public bool HasTile(TileCorner corner, out uint8 variatioCount) => variations.TryGetValue(corner, out variatioCount);

		public Animation GetAnimation(String name)
		{
			if (animations.TryGetValue(name, let anim))
				return anim;

			Runtime.FatalError(scope $"Animation {name} couldn't be found");
		}

		[Inline]
		public void Draw(Batch2D batch, int frame, int variation, TileCorner corner, Vector2 position, Vector2 scale = .One, float rotation = 0, Color color = .White)
		{
			{
				Debug.Assert(variations.TryGetValue(corner, let variationCount));
				Debug.Assert(variationCount > variation);
			}

			let tile = tiles[(uint16)corner + ((uint16)variation << 8)];
			batch.Image(frames[frame].Texture, tile.Clip, position, scale, .Zero, rotation, color);
		}
	}
}
