using System;
using System.Collections;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	enum TileConnection : uint8
	{
		None = 0,
		Left = 1,
		Right = 1 << 2,
		Up = 1 << 3,
		Down = 1 << 4,

		All = Left | Right | Up | Down
	}

	class Tileset
	{
		public struct Animation
		{
			public readonly int From;
			public readonly int To;
		}

		public struct Tile
		{
			public readonly UPoint2 Offset;
			public readonly Rect Clip;

			public this(UPoint2 offset, Rect clip)
			{
				Offset = offset;
				Clip = clip;
			}
		}

		public struct Frame
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

		public readonly uint Spacing;
		public readonly UPoint2 TileSize;

		Frame[] frames ~ delete _;
		Dictionary<String, Animation> animations ~ delete _;

		// For a given tile configuration, get the number of variations and frames
		Dictionary<TileConnection, uint8> variations = new .() ~ delete _;

		// The key here is connection + (variation << 8)
		Dictionary<uint16, Tile> tiles = new .() ~ delete _;

		public this(Span<Frame> frameSpan, Span<(TileConnection conn, UPoint2 tileOffset)> tileSpan, Span<(String name, Animation anim)> animSpan, UPoint2 tileSize, uint spacing = 0)
		{
			Debug.Assert(frameSpan.Length > 0, "Sprite has to have at least one frame");

			frames = new Frame[frameSpan.Length];
			if (frameSpan.Length > 0) frameSpan.CopyTo(frames);

			Spacing = spacing;
			TileSize = tileSize;

			for (let tup in tileSpan)
			{
				// Update variation count
				uint8 variation = 1;
				if (variations.TryGetValue(tup.conn, let val))
					variation = variations[tup.conn] = val + 1;
				else variations.Add(tup.conn, 1);

				// Put combination in tiles lookup
				tiles.Add(((uint16)tup.conn + ((uint16)variation << 8)),
					Tile(tup.tileOffset,
					Rect(tup.tileOffset * TileSize + (tup.tileOffset + .One) * Spacing, TileSize)));
			}

			for (let tup in animSpan)
				animations.Add(tup.name, tup.anim);
		}

		[Inline]
		public bool HasAnimation(String name) => animations.ContainsKey(name);

		public Animation GetAnimation(String name)
		{
			if (animations.TryGetValue(name, let anim))
				return anim;

			Runtime.FatalError(scope $"Animation {name} couldn't be found");
		}

		[Inline]
		public void Draw(Batch2D batch, int frame, int variation, TileConnection connection, Vector2 position, Vector2 scale = .One, float rotation = 0, Color color = .White)
		{
			let tile = tiles[(uint16)connection + ((uint16)variations[connection] << 8)];
			batch.Image(frames[frame].Texture, tile.Clip, position, scale, -(TileSize / 2) , rotation, color);
		}
	}
}
