using System;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	[CompSerializable]
	struct TriggerBody
	{
		public int triggerCount;
		public TriggerRect[16] triggers;

		public int overlapCount;
		public TriggerCollisionInfo[16] overlaps;
		public int prevOverlapCount;
		public TriggerCollisionInfo[16] prevOverlaps;

		public int newOverlapCount;
		public TriggerCollisionInfo[8] newOverlaps;

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

	[CompSerializable]
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

	[CompSerializable]
	struct TriggerOverlapFeedback
	{
		public int overlapCount;
		public TriggerCollisionInfo[16] overlaps;

		public int newOverlapCount;
		public TriggerCollisionInfo[8] newOverlaps;
	}

	[CompSerializable]
	struct TriggerCollisionInfo
	{
		public Entity other;
		public int myColliderIndex, otherColliderIndex;
	}

	class TriggerFeedbackSystem : ComponentSystem
	{
		static Type[?] wantsComponents = .(typeof(TriggerOverlapFeedback));
		this
		{
			signatureTypes = wantsComponents;
		}

		public void TickPreTriggerSys()
		{
			// To be triggered before TriggerSystem!

			for (let e in entities)
			{
				let feed = componentManager.GetComponent<TriggerOverlapFeedback>(e);

				// Reset overlaps
				feed.newOverlapCount = feed.overlapCount = 0;

#if DEBUG // Technically we dont actually need to clear these, since we always override and check for count
				feed.overlaps = .();
				feed.newOverlaps = .();
#endif
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
			if (!debugRenderTriggers)
				return;

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

				trib.prevOverlapCount = trib.overlapCount;
				trib.overlapCount = 0;
				trib.prevOverlaps = trib.overlaps;
#if DEBUG
				trib.overlaps = .();
#endif

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
										Debug.Assert(trib.overlapCount < trib.overlaps.Count - 1, "Too many trigger overlaps to record in TriggerBody / TriggerOverlapFeedback");

										trib.overlaps[trib.overlapCount++] = .()
											{
												other = eC,
												myColliderIndex = ti,
												otherColliderIndex = ci
											};

										if (componentManager.GetComponentOptional<TriggerOverlapFeedback>(eC, let feedback))
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

				trib.newOverlapCount = 0;
#if DEBUG
				trib.newOverlaps = .();
#endif

				for (let ci < trib.overlapCount)
				{
					let cOverlap = trib.overlaps[ci];
					bool isOld = false;
					for (let pi < trib.prevOverlapCount)
					{
						let pOverlap = trib.prevOverlaps[pi];

						if (cOverlap.other == pOverlap.other && cOverlap.myColliderIndex == pOverlap.myColliderIndex && cOverlap.otherColliderIndex == pOverlap.otherColliderIndex)
							isOld = true;
					}

					// This overlap is new, add it to the new list
					if (!isOld)
					{
						Debug.Assert(trib.newOverlapCount < trib.newOverlaps.Count - 1, "Too many *new* trigger overlaps to record in TriggerBody / TriggerOverlapFeedback");

						trib.newOverlaps[trib.newOverlapCount++] = cOverlap;

						if (componentManager.GetComponentOptional<TriggerOverlapFeedback>(cOverlap.other, let feedback))
							// Technically we've already added this to the feedback.overlaps list somewhere, but we're not going to search, just make it again
							feedback.newOverlaps[feedback.newOverlapCount++] = .()
								{
									other = e,
									myColliderIndex = cOverlap.otherColliderIndex,
									otherColliderIndex = cOverlap.myColliderIndex
								};
					}
				}
			}
		}
	}
}
