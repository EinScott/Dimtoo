using System;
using System.Diagnostics;
using Pile;
using FastNoiseLite;

namespace Dimtoo
{
	[Serializable]
	struct GridCollider
	{
		public LayerMask layer;

		public Point2 offset;
		public UPoint2 cellSize;
		public bool[MAX_CELL_AXIS][MAX_CELL_AXIS] cells;
		public const int MAX_CELL_AXIS = 128;

		bool gridDirty;
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
		static Type[?] wantsComponents = .(typeof(Transform), typeof(GridCollider));
		this
		{
			signatureTypes = wantsComponents;
		}

		public bool debugRenderGrid;
		public Camera2D renderClip;

		public int GetRenderLayer()
		{
			return 997;
		}

		public void Render(Batch2D batch)
		{
			if (!debugRenderGrid)
				return;

			Debug.Assert(renderClip != null);

			for (let e in entities)
			{
				let tra = componentManager.GetComponent<Transform>(e);
				let gri = componentManager.GetComponent<GridCollider>(e);
				
				let pos = tra.position.Round();
				let bounds = gri.GetBounds(pos);
				batch.HollowRect(bounds, 1, .Gray);

				let cellMin = Point2.Max(renderClip.CameraRect.Position / gri.cellSize, bounds.Position);
				let cellMax = Point2.Min((renderClip.CameraRect.Position + renderClip.CameraRect.Size) / gri.cellSize, (bounds.Position + bounds.Size)) + .One;

				for (var y = cellMin.Y; y < cellMax.Y; y++)
					for (var x = cellMin.X; x < cellMax.X; x++)
						if (gri.cells[y][x])
							batch.HollowRect(gri.GetCollider(x, y, pos), 1, .Red);
			}
		}

		[Optimize]
		public static Rect MakeGridCellBoundsRect(GridCollider* grid)
		{
			// In cell units!
			var origin = Point2.Zero;
			var size = Point2.Zero;

			// Get grid tile bounds
			Point2 min = .(GridCollider.MAX_CELL_AXIS), max = default;
			for (let y < GridCollider.MAX_CELL_AXIS)
				for (let x < GridCollider.MAX_CELL_AXIS)
					if (grid.cells[y][x])
					{
						if (x < min.X) min.X = x;
						if (x > max.X) max.X = x;

						if (y < min.Y) min.Y = y;
						if (y > max.Y) max.Y = y;
					}

			max += .One;

			origin = min;
			size = max - min;

			return Rect(origin, size);
		}
	}

	//[Serializable]
	struct TileRenderer
	{
		public Asset<Tileset> tileset;

		public this(Asset<Tileset> tileset)
		{
			this.tileset = tileset;
		}	
	}

	class TileRenderSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(TileRenderer), typeof(GridCollider), typeof(Transform));
		this
		{
			signatureTypes = wantsComponents;
		}

		public int GetRenderLayer()
		{
			return -10;
		}

		FastNoiseLite noise =
			{
				let n = new FastNoiseLite();
				n.SetFrequency(1);

				n
			} ~ delete _;

		public Camera2D renderClip;

		public void Render(Batch2D batch)
		{
			for (let e in entities)
			{
				let tra = componentManager.GetComponent<Transform>(e);
				let gri = componentManager.GetComponent<GridCollider>(e);
				let tir = componentManager.GetComponent<TileRenderer>(e);

				if (tir.tileset == null)
					continue;

				let pos = tra.position.Round();
				let bounds = gri.GetBounds(pos);

				let cellMin = Point2.Max(renderClip.CameraRect.Position / gri.cellSize, bounds.Position);
				let cellMax = Point2.Min((renderClip.CameraRect.Position + renderClip.CameraRect.Size) / gri.cellSize, (bounds.Position + bounds.Size)) + .One;

				// TODO: animations, variants

				let originPos = pos + gri.offset - (gri.cellSize / 2);
				for (var y = cellMin.Y; y < cellMax.Y + 1; y++)
					for (var x = cellMin.X; x < cellMax.X + 1; x++)
					{
						TileCorner corner = .None;
						if (x - 1 >= 0 && y - 1 >= 0 && gri.cells[y - 1][x - 1])
							corner |= .TopLeft;
						if (x < GridCollider.MAX_CELL_AXIS && y - 1 >= 0 && gri.cells[y - 1][x])
							corner |= .TopRight;
						if (x - 1 >= 0 && y < GridCollider.MAX_CELL_AXIS && gri.cells[y][x - 1])
							corner |= .BottomLeft;
						if (x < GridCollider.MAX_CELL_AXIS && y < GridCollider.MAX_CELL_AXIS && gri.cells[y][x])
							corner |= .BottomRight;

						mixin GetVariation(int variationCount)
						{
							(int)(((noise.GetNoise(x, y) + 1) / 2) * (variationCount - 0.001f))
						}

						let tilePos = originPos + .(x, y) * gri.cellSize;
						let tileset = tir.tileset.Asset;
						if (tileset.HasTile(corner, let variationCount))
							tileset.Draw(batch, 0, GetVariation!(variationCount), corner, tilePos);
						else
						{
							// Assemble from separate tiles?

							if ((corner & .TopLeft) != 0 && (corner & .BottomRight) != 0
								&& tileset.HasTile(.TopLeft, let tlVariationCount) && tileset.HasTile(.BottomRight, let brVariationCount))
							{
								tileset.Draw(batch, 0, GetVariation!(tlVariationCount), .TopLeft, tilePos);
								tileset.Draw(batch, 0, GetVariation!(brVariationCount), .BottomRight, tilePos);
							}
							else if ((corner & .TopRight) != 0 && (corner & .BottomLeft) != 0
								&& tileset.HasTile(.TopRight, let trVariationCount) && tileset.HasTile(.BottomLeft, let blVariationCount))
							{
								tileset.Draw(batch, 0, GetVariation!(trVariationCount), .TopRight, tilePos);
								tileset.Draw(batch, 0, GetVariation!(blVariationCount), .BottomLeft, tilePos);
							}
							else
							{
								// Nothing found
								batch.Rect(.(tilePos, tileset.TileSize), .Magenta);
							}
						}
					}
			}
		}
	}
}
