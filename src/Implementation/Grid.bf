using System;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	[Serializable]
	struct GridRenderer
	{

	}

	class GridRenderSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(GridRenderer), typeof(CollisionBody), typeof(Transform));
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
