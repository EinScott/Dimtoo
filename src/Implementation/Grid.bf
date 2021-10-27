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
	struct TileRenderer
	{
		
	}

	class TileRenderSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(TileRenderer), typeof(CollisionBody), typeof(Transform));
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
				let cob = componentManager.GetComponent<CollisionBody>(e);

				Debug.Assert(cob.collider case .Grid);

				if (cob.collider case .Grid(let offset,let cellX,let cellY,let collide))
				{
					Vector2 origin = tra.position + offset;
					Point2 size = .(cellX, cellY);
					for (let y < 32)
						for (let x < 32)
							if (collide[y*32+x])
							{
								
							}
				}
			}*/
		}
	}
}
