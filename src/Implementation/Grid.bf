using System;
using System.Diagnostics;
using Pile;

// TODO:
// separate ColliderRect and Grid!
// grid needs to be its own this for us to have it here
// the grid should not be bound to collision! we need it for rendering
// -> so we may need different system just for keeping a list of (GridBody, Grid)
//    GridBody has LayerMask, but does not provide a chance to move!
// -> pass that system into Resolve!

// TODO: also tileset importer

namespace Dimtoo
{
	[Serializable]
	struct Grid
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
		static Type[?] wantsComponents = .(typeof(Transform), typeof(Grid));
		this
		{
			signatureTypes = wantsComponents;
		}

		public bool debugRenderGrid;

		public int GetRenderLayer()
		{
			return 997;
		}

		public void Render(Batch2D batch)
		{
			if (!debugRenderGrid)
				return;

			for (let e in entities)
			{
				let tra = componentManager.GetComponent<Transform>(e);
				let gri = componentManager.GetComponent<Grid>(e);

				batch.HollowRect(gri.GetBounds(tra.position.Round()), 1, .Gray);

				// TODO: optimize, this renders way too much
				let origin = tra.position.Round() + gri.offset;
				Point2 size = gri.cellSize;
				let bounds = gri.GetCellBounds();
				for (var y = bounds.Y; y < bounds.Y + bounds.Height; y++)
					for (var x = bounds.X; x < bounds.X + bounds.Width; x++)
						if (gri.cells[y][x])
							batch.HollowRect(.((origin + .(x,y) * gri.cellSize), size), 1, .Red);
			}
		}

		[Optimize]
		public static Rect MakeGridCellBoundsRect(Grid* grid)
		{
			// In cell units!
			var origin = Point2.Zero;
			var size = Point2.Zero;

			// Get grid tile bounds
			Point2 min = .(Grid.MAX_CELL_AXIS), max = default;
			for (let y < Grid.MAX_CELL_AXIS)
				for (let x < Grid.MAX_CELL_AXIS)
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

	[Serializable]
	struct TileRenderer
	{
		
	}

	class TileRenderSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(TileRenderer), typeof(Grid), typeof(Transform));
		this
		{
			signatureTypes = wantsComponents;
		}

		public int GetRenderLayer()
		{
			return -10;
		}

		public void Render(Batch2D batch)
		{
			/*for (let e in entities)
			{
				let gridRend = componentManager.GetComponent<GridRenderer>(e);
				let tra = componentManager.GetComponent<Transform>(e);
				let gri = componentManager.GetComponent<Grid>(e);

				
			}*/
		}
	}
}
