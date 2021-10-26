using System;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	// - triggers system! -- each component will know from state if an overlap is new or old!

	struct TriggerBody
	{
		public int triggerCount;
		public TriggerRect[16] triggers;

		public int overlapCount;
		public TriggerCollisionInfo[32] overlaps;

		public this(params TriggerRect[] colls)
		{
			this = default;

			Debug.Assert(colls.Count <= triggers.Count);

			triggerCount = colls.Count;
			triggers = .();
			for (let i < colls.Count)
				triggers[i] = colls[i];
		}
	}

	struct TriggerRect
	{
		public this(Rect rect, LayerMask layer = 0x1)
		{
			this.rect = rect;
			this.layer = layer; // By default on layer 0
		}

		public Rect rect;
		public LayerMask layer;
	}

	// TODO: cobs move into triggers
	struct TriggerEnterFeedback
	{
		public int overlapCount;
		public TriggerCollisionInfo[16] overlaps;
	}

	struct TriggerCollisionInfo
	{
		public Entity other;
		public int myColliderIndex, otherColliderIndex;
	}

	class TriggerFeedbackSystem : ComponentSystem
	{
		static Type[?] wantsComponents = .(typeof(TriggerEnterFeedback));
		this
		{
			signatureTypes = wantsComponents;
		}

		public void TickPreTriggerSys()
		{
			// To be triggered before TriggerSystem!

			for (let e in entities)
			{
				let feed = componentManager.GetComponent<TriggerEnterFeedback>(e);

				// Reset overlaps?
				feed.overlapCount = 0;
				feed.overlaps = .();
			}
		}
	}

	class TriggerSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(Transform), typeof(TriggerBody));
		this
		{
			signatureTypes = wantsComponents;
		}

		public int GetRenderLayer()
		{
			return 998;
		}

		public bool debugRenderTriggers;

		public void Render(Batch2D batch)
		{
			for (let e in entities)
			{
				let tra = componentManager.GetComponent<Transform>(e);
				let trib = componentManager.GetComponent<TriggerBody>(e);

				for (let ti < trib.triggerCount)
					batch.HollowRect(.(tra.position.Round() + trib.triggers[ti].rect.Position, trib.triggers[ti].rect.Size), 1, .Blue);
			}
		}

		public void TickPostColl(CollisionSystem collSys)
		{
			// We assume to be called after movement has taken place, otherwise updating triggers wouldn't make sense
			// i.e.: (various updates adding force, setting movement) -> collision tick & other movement finalizing things
			//		 -> trigger tick -> ... (movement & now also contact info fresh for next cycle)

			for (let e in entities)
			{
				let tra = componentManager.GetComponent<Transform>(e);
				let trib = componentManager.GetComponent<TriggerBody>(e);

				trib.overlapCount = 0;
				trib.overlaps = .();

				for (let eC in collSys.entities)
				{
					let traC = componentManager.GetComponent<Transform>(eC);
					let cob = componentManager.GetComponent<CollisionBody>(eC);

					for (let ti < trib.triggerCount)
					{
						switch (cob.collider)
						{
						case .Rect(let count,let colliders):
							for (let ci < count)
								if (trib.triggers[ti].layer.Overlaps(colliders[ci].layer))
								{
									let tRect = Rect(tra.position.Round() + trib.triggers[ti].rect.Position, trib.triggers[ti].rect.Size);
									let cRect = Rect(traC.position.Round() + colliders[ci].rect.Position, colliders[ci].rect.Size);

									if (tRect.Overlaps(cRect))
									{
										trib.overlaps[trib.overlapCount++] = .()
											{
												other = eC,
												myColliderIndex = ti,
												otherColliderIndex = ci
											};

										if (componentManager.GetComponentOptional<TriggerEnterFeedback>(eC, let feedback))
										{
											feedback.overlaps[feedback.overlapCount++] = .()
												{
													other = e,
													otherColliderIndex = ti,
													myColliderIndex = ci
												};
										}
									}
								}
						case .Grid(let offset,let cellX,let cellY,let collide):
							Debug.FatalError();
						}
					}
				}
			}
		}
	}
}
