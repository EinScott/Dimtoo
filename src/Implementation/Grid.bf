using System;
using System.Diagnostics;
using Pile;
using FastNoiseLite;
using Bon;

namespace Dimtoo
{
	// TODO: incorporate tile flags into the tile image deciding process somehow -- optionally, either directly in the tileset file or via some function ptr
	// OR maybe not, but still have them
	// alternetively feed more TileCorner, 3x3 into the decider?
	// -> flag system would be nicer, more possibilities
	// -> problem with that is: how to we distribute these flags?
	// -> do we have some flags pass when dirty? -- i mean that doesnt sound so bad! -> we just got new bounds, now check everything for tags!
	// -> have a propagation system with "newFlags? func(TilePos (like .Top, .TopLeft), newFlags)" and if a adjacent tile to a change decides to change, call its adjacent funcs too
	//    ... in the hopes that it eventually stops? i dunno about that, it kind of screams stack overflow / infinite loop.
	// -> what did old pile do again?

	// make a combination of auto tiling and considering flags when picking a tile!
	// -> flags for different tile types (when selecting edge sprite, just take that into account! - possibly make an enum to help!)
	// -> auto tiling for changing flags based on sourrounding tiles (and return if adjacent need to be updated)

	// maybe we shouldn't use transform for grids? or at least something in addition - or just grid component
	// -> in any case, it shouldn't be freely movable with that component (maybe TransformTile or something)
	// -> that allows us there to query the nearby tiled grids if something happens on the edged, and update them
	//    if existant -- works, it it worth it / simpler solution?

	[BonTarget]
	struct Tile : uint8
	{
		public const Tile None = default;
		public const Tile Solid = solidMask;
		const uint8 solidMask = 0b1;

		[Inline]
		public bool IsSolid => (uint8)this & solidMask > 0;

		[Inline]
		public uint8 /* - more like 7 */ Flags => (uint8)this >> 1;
	}

	// TODO: per "type of tile" collMask...?
	// -> would be useful... i think?

	[BonTarget,BonPolyRegister]
	struct Grid
	{
		public LayerMask layer;

		public Point2 offset;
		public UPoint2 cellSize;
		public Tile[MAX_CELL_AXIS][MAX_CELL_AXIS] cells;
		public const int MAX_CELL_AXIS = 128;

		[BonInclude]
		bool gridDirty;
		[BonInclude]
		Rect cellBounds;

		public this(UPoint2 cellSize, LayerMask layer = 0x1)
		{
			this = default;
			this.cellSize = cellSize;
			this.layer = layer;
		}

		[Inline]
		public void MarkDirty() mut
		{
			gridDirty = true;
		}

		[Inline]
		public Rect GetBounds(Point2 pos) mut
		{
			if (gridDirty)
			{
				cellBounds = GridSystem.MakeGridCellBoundsRect(&this);
				gridDirty = false;
			}

			return Rect(cellBounds.Position * cellSize + pos + offset, cellBounds.Size * cellSize);
		}

		public (Point2 cellMin, Point2 cellMax) GetCellBoundsOverlapping(Point2 pos, Rect clipRect) mut
		{
			if (gridDirty)
			{
				cellBounds = GridSystem.MakeGridCellBoundsRect(&this);
				gridDirty = false;
			}

			let cellMin = Point2.Max((clipRect.Position - pos - offset) / cellSize, cellBounds.Position);
			let cellMax = Point2.Min(((clipRect.Position - pos - offset) + clipRect.Size) / cellSize + .One, cellBounds.Position + cellBounds.Size);

			return (cellMin, cellMax);
		}

		[Inline]
		public Rect GetCellBounds() mut
		{
			if (gridDirty)
			{
				cellBounds = GridSystem.MakeGridCellBoundsRect(&this);
				gridDirty = false;
			}

			return cellBounds;
		}

		public Rect GetCollider(int index, Point2 pos)
		{
			Debug.Assert((uint)index < (uint)512*512);
			let x = index % 512;
			let y = (index - x) / 512;
			Debug.Assert(x < 512 && y < 512);
			return .(pos + offset + .(x, y) * cellSize, cellSize);
		}

		[Inline]
		public Rect GetCollider(int x, int y, Point2 pos)
		{
			Debug.Assert(x < 512 && y < 512);
			return .(pos + offset + .(x, y) * cellSize, cellSize);
		}

		[Inline]
		public static int GetGridIndex(int x, int y)
		{
			return y * 512 + x;
		}
	}

	class GridSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(Transform), typeof(Grid));
		this
		{
			signatureTypes = wantsComponents;
		}

		public bool debugRenderGrid;

		public float GetRenderLayer()
		{
			return 20;
		}

		[PerfTrack("Dimtoo:DebugRender")]
		public void Render(Batch2D batch)
		{
			if (!debugRenderGrid)
				return;

			Debug.Assert(scene.camFocus != null);

			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let gri = scene.GetComponent<Grid>(e);
				
				let pos = tra.point;
				let bounds = gri.GetBounds(pos);
				if (bounds.Area != 0)
					batch.HollowRect(bounds, 1, .Gray);

				(let cellMin, let cellMax) = gri.GetCellBoundsOverlapping(pos, scene.camFocus.CameraRect);

				for (var y = cellMin.Y; y < cellMax.Y; y++)
					for (var x = cellMin.X; x < cellMax.X; x++)
						if (gri.cells[y][x].IsSolid)
							batch.HollowRect(gri.GetCollider(x, y, pos), 1, .Red);
			}
		}

		[Optimize]
		public static Rect MakeGridCellBoundsRect(Grid* grid)
		{
			// Get grid tile bounds
			Point2 min = .(Grid.MAX_CELL_AXIS), max = default;
			for (let y < Grid.MAX_CELL_AXIS)
				for (let x < Grid.MAX_CELL_AXIS)
					if (grid.cells[y][x].IsSolid)
					{
						if (x < min.X) min.X = x;
						if (x > max.X) max.X = x;

						if (y < min.Y) min.Y = y;
						if (y > max.Y) max.Y = y;
					}

			if (max == default && min == .(Grid.MAX_CELL_AXIS))
				return .Zero;

			max += .One;

			return Rect(min, max - min);
		}
	}

	[BonTarget]
	struct TilerLayerRenderInfo
	{
		public int renderLayer;
		public bool renderDepthSorted;
		public Asset<Tileset> tileset;
	}
	
	[BonTarget,BonPolyRegister]
	struct TileRenderer
	{
		public TilerLayerRenderInfo[2] layers;

		public this(params Asset<Tileset>[2] tilesets)
		{
			layers = default;
			for (let i < layers.Count)
				layers[i].tileset = tilesets[i];
		}
	}

	class TileRenderSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(TileRenderer), typeof(Grid), typeof(Transform));
		this
		{
			signatureTypes = wantsComponents;
		}

		public float GetRenderLayer()
		{
			return -10;
		}

		FastNoiseLite noise =
			{
				let n = new FastNoiseLite();
				n.SetFrequency(1);

				n
			} ~ delete _;

		public Camera2D cam;

		[PerfTrack]
		public void Render(Batch2D batch)
		{
			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let gri = scene.GetComponent<Grid>(e);
				let tir = scene.GetComponent<TileRenderer>(e);

				let pos = tra.point;
				(let cellMin, let cellMax) = gri.GetCellBoundsOverlapping(pos, cam.CameraRect);

				// TODO: animations, variants

				for (let t < tir.layers.Count)
				{
					var layer = tir.layers[t];

					if (layer.tileset.Asset == null)
						continue;
					let tileset = layer.tileset.Asset;

					if (!layer.renderDepthSorted)
						batch.SetLayer((.)layer.renderLayer);

					let originPos = pos + gri.offset - (gri.cellSize / 2);
					for (var y = cellMin.Y; y < cellMax.Y + 1; y++)
					{
						if (layer.renderDepthSorted)
							batch.SetLayer((.)layer.renderLayer + (((float)originPos.Y - cam.Bottom - cam.Viewport.Y / 2 + (y + 0.75f) * gri.cellSize.Y) / cam.Viewport.Y)); // TODO: maybe make the 1.5f variable?

						for (var x = cellMin.X; x < cellMax.X + 1; x++)
						{
							TileCorner corner = .{
								tiles = .(
									x - 1 >= 0 && y - 1 >= 0 ? gri.cells[y - 1][x - 1] : .None,
									x < Grid.MAX_CELL_AXIS && y - 1 >= 0 ? gri.cells[y - 1][x] : .None,
									x - 1 >= 0 && y < Grid.MAX_CELL_AXIS ? gri.cells[y][x - 1] : .None,
									x < Grid.MAX_CELL_AXIS && y < Grid.MAX_CELL_AXIS ? gri.cells[y][x] : .None)
							};

							mixin GetVariation(int variationCount)
							{
								(int)(((noise.GetNoise(x, y) + 1) / 2) * (variationCount - 0.001f))
							}

							let tilePos = originPos + .(x, y) * gri.cellSize;
							if (tileset.HasTile(corner, let variationCount))
								tileset.Draw(batch, 0, GetVariation!(variationCount), corner, tilePos);
							else do
							{
								// Assemble from separate tiles?

								if (corner.tiles[0] != .None && corner.tiles[1] == .None && corner.tiles[2] == .None && corner.tiles[3] != .None)
								{
									let topLeft = TileCorner{tiles = .(corner.tiles[0],)};
									let bottomRight = TileCorner{tiles = .(default, default, default, corner.tiles[3])};
									if (tileset.HasTile(topLeft, let tlVariationCount)
									&& tileset.HasTile(bottomRight, let brVariationCount))
									{
										tileset.Draw(batch, 0, GetVariation!(tlVariationCount), topLeft, tilePos);
										tileset.Draw(batch, 0, GetVariation!(brVariationCount), bottomRight, tilePos);
										break;
									}
								}
								else if (corner.tiles[0] == .None && corner.tiles[1] != .None && corner.tiles[2] != .None && corner.tiles[3] == .None)
								{
									let topRight = TileCorner{tiles = .(default, corner.tiles[1],)};
									let bottomLeft = TileCorner{tiles = .(default, default, corner.tiles[2],)};
									if (tileset.HasTile(topRight, let tlVariationCount)
									&& tileset.HasTile(bottomLeft, let brVariationCount))
									{
										tileset.Draw(batch, 0, GetVariation!(tlVariationCount), topRight, tilePos);
										tileset.Draw(batch, 0, GetVariation!(brVariationCount), bottomLeft, tilePos);
										break;
									}
								}

								// Nothing found
								batch.Rect(.(tilePos, tileset.TileSize), .Magenta);
							}
						}
					}
				}
			}
		}
	}
}
