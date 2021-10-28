using System;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	[Serializable]
	struct TriggerBody
	{
		public SizedList<TriggerRect, const 16> triggers;

		public SizedList<TriggerCollisionInfo, const 16> overlaps;
		public SizedList<TriggerCollisionInfo, const 16> prevOverlaps;

		public SizedList<TriggerCollisionInfo, const 8> newOverlaps;

		public this(params TriggerRect[] colls)
		{
			this = default;

			for (let i < colls.Count)
				triggers.Add(colls[i]);
		}
	}

	[Serializable]
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

	[Serializable]
	struct TriggerOverlapFeedback
	{
		public SizedList<TriggerCollisionInfo, const 16> overlaps;
		public SizedList<TriggerCollisionInfo, const 8> newOverlaps;
	}

	[Serializable]
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
				feed.overlaps.Clear();
				feed.newOverlaps.Clear();
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

				for (let t in trib.triggers)
					batch.HollowRect(.(tra.position.Round() + t.rect.Position, t.rect.Size), 1, .Blue);
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

				trib.prevOverlaps = trib.overlaps;
				trib.overlaps.Clear();

				for (let eC in collSys.entities)
				{
					let traC = componentManager.GetComponent<Transform>(eC);
					let cob = componentManager.GetComponent<CollisionBody>(eC);

					for (let trig in trib.triggers)
					{
						let tRect = Rect(tra.position.Round() + trig.rect.Position, trig.rect.Size);

						for (let coll in cob.colliders)
							if (trig.layer.Overlaps(coll.layer))
							{
								let cRect = Rect(traC.position.Round() + coll.rect.Position, coll.rect.Size);

								if (tRect.Overlaps(cRect))
								{
									trib.overlaps.Add(TriggerCollisionInfo()
										{
											other = eC,
											myColliderIndex = @trig.Index,
											otherColliderIndex = @coll.Index
										});

									if (componentManager.GetComponentOptional<TriggerOverlapFeedback>(eC, let feedback))
									{
										feedback.overlaps.Add(TriggerCollisionInfo()
											{
												other = e,
												otherColliderIndex = @trig.Index,
												myColliderIndex = @coll.Index
											});
									}
								}
							}
					}
				}

				trib.newOverlaps.Clear();

				for (let currOver in trib.overlaps)
				{
					bool isOld = false;
					for (let prevOver in trib.prevOverlaps)
					{
						if (currOver.other == prevOver.other && currOver.myColliderIndex == prevOver.myColliderIndex && currOver.otherColliderIndex == prevOver.otherColliderIndex)
							isOld = true;
					}

					// This overlap is new, add it to the new list
					if (!isOld)
					{
						trib.newOverlaps.Add(currOver);

						if (componentManager.GetComponentOptional<TriggerOverlapFeedback>(currOver.other, let feedback))
							// Technically we've already added this to the feedback.overlaps list somewhere, but we're not going to search, just make it again
							feedback.newOverlaps.Add(TriggerCollisionInfo()
								{
									other = e,
									myColliderIndex = currOver.otherColliderIndex,
									otherColliderIndex = currOver.myColliderIndex
								});
					}
				}
			}
		}
	}
}
