using System;
using Pile;
using Bon;

namespace Dimtoo
{
	// Unused because we can still just use masks...
	// -> cannot handle mask like layers.. but for now masks are still fine
	// -> compare: things have actual layers instead of "dimensions on which they interact", the layers define the interactions with other defined layers

	// This kiund of undermines the thing and is just another layer on the config pile...
	/*struct SimLayerCollection
	{
		public const Self NONE = default;
		public const Self ALL = .(uint64.MaxValue);

		public this(uint64 mask = 0x1)
		{
			val = mask;
		}

		[BonInclude]
		uint64 val;

		public bool this[SimLayer layer]
		{
			[Inline]
			get => (val & (uint64)(1 << (uint8)layer)) > 0;
			set mut => val |= (uint64)(1 << (uint8)layer);
		}

		[Inline]
		public bool Overlaps(Self other) => (val & other.val) > 0;

		[Inline]
		public Self Combine(Self other) => .(val | other.val);

		[Inline]
		public static implicit operator Self(uint64 i)
		{
			Self m = default;
			m.val = i;
			return m;
		}
	}

	[BonTarget]
	struct SimLayer : uint8
	{
		public const Self DEFAULT = 0;

		public static implicit operator int(Self l) => (uint8)l;
#unwarn
		public static implicit operator Self(uint8 i) => *(Self*)&i;
	}

	[BonTarget]
	struct LayerMatrix
	{
		static this
		{
			Compiler.Assert(LAYER_COUNT % 2 == 0);
		}

		[Comptime]
		static bool[LAYER_COUNT / 2][LAYER_COUNT + 1] Setup()
		{
			LayerMatrix layerm = default;
			for (SimLayer l < LAYER_COUNT) // 0 collides with everything
				layerm[0, l] = true;

			return layerm.lookup;
		}

		public const uint8 LAYER_COUNT = 64;
		const bool[LAYER_COUNT / 2][LAYER_COUNT + 1] defaultLookup = Setup();

		public bool[LAYER_COUNT / 2][LAYER_COUNT + 1] lookup;

		(int xLook, int yLook) Convert(SimLayer a, SimLayer b)
		{
			int yLook = a > b ? b : a, max = a > b ? a : b, xLook;
			if (yLook < LAYER_COUNT / 2)
				xLook = LAYER_COUNT - max - 1;
			else
			{
				yLook = LAYER_COUNT - yLook - 1;
				xLook = max + 1;
			}

			return (xLook, yLook);
		}

		public bool this[SimLayer a, SimLayer b]
		{
			get
			{
				let (xLook, yLook) = Convert(a, b);
				return lookup[yLook][xLook];
			}

			set mut
			{
				let (xLook, yLook) = Convert(a, b);
				lookup[yLook][xLook] = value;
			}
		}
	}*/

	/* From Collision.bf for reference / preservation

	[Optimize]
	public static Rect MakeColliderBounds(Scene scene, Point2 pos, ColliderList colliders, SimLayerCollection layers = .ALL)
	{
		var origin = pos;
		var size = Point2.Zero;

		// Get bounds
		for (let coll in colliders)
		{
			bool overlapsAny = false;
			for (SimLayer layer < LayerMatrix.LAYER_COUNT)
				if (layers[layer])
					overlapsAny |= scene.layerMatrix[coll.layer, layer];

			if (!overlapsAny)
				continue;

			let boxOrig = pos + coll.rect.Position;

			// Leftmost corner
			if (boxOrig.X < origin.X)
				origin.X = boxOrig.X;
			if (boxOrig.Y < origin.Y)
				origin.Y = boxOrig.Y;

			// Size
			let boxSize = coll.rect.Size;
			if (boxOrig.X + boxSize.X > origin.X + size.X)
				size.X = boxSize.X;
			if (boxOrig.Y + boxSize.Y > origin.Y + size.Y)
				size.Y = boxSize.Y;
		}

		return .(origin, size);
	}

	[Optimize]
	// For non-mover entities, this just returns bounds
	public static Rect MakePathRect(Scene scene, ResolveSet s, SimLayerCollection layers = .ALL)
	{
		var bounds = MakeColliderBounds(scene, s.pos, s.coll, layers);

		// Expand by movement
		if (s.move != .Zero)
		{
			bounds.Size += Point2.Abs(s.move);
			if (s.move.X < 0)
				bounds.X += s.move.X;
			if (s.move.Y < 0)
				bounds.Y += s.move.Y;
		}

		return bounds;
	}

	*/
}