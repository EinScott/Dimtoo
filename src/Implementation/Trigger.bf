using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	// TODO: circular triggers

	[BonTarget,BonPolyRegister]
	struct TriggerBody
	{
		public SizedList<TriggerRect, const 4> triggers;

		public SizedList<TriggerCollisionInfo, const 8> overlaps;
		public SizedList<TriggerCollisionInfo, const 8> prevOverlaps;

		public SizedList<TriggerCollisionInfo, const 8> newOverlaps;

		public this(params TriggerRect[] colls)
		{
			this = default;

			for (let i < colls.Count)
				triggers.Add(colls[i]);
		}
	}

	[BonTarget]
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

	[BonTarget,BonPolyRegister]
	struct TriggerOverlapFeedback
	{
		public SizedList<TriggerCollisionInfo, const 8> overlaps;
		public SizedList<TriggerCollisionInfo, const 8> newOverlaps;
	}

	[BonTarget]
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
				let feed = scene.GetComponent<TriggerOverlapFeedback>(e);

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

		public float GetRenderLayer()
		{
			return 20;
		}

		public bool debugRenderTriggers;

		[PerfTrack("Dimtoo:DebugRender")]
		public void Render(Batch2D batch)
		{
			if (!debugRenderTriggers)
				return;

			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let trib = scene.GetComponent<TriggerBody>(e);

				for (let t in trib.triggers)
					batch.HollowRect(.(tra.point + t.rect.Position, t.rect.Size), 1, .Blue);
			}
		}

		[PerfTrack] // 0.09/0.10 ms before
		public void TickPostColl(BucketSystem buckSys)
		{
			// We assume to be called after movement has taken place, otherwise updating triggers wouldn't make sense
			// i.e.: (various updates adding force, setting movement) -> collision tick & other movement finalizing things
			//		 -> trigger tick -> ... (movement & now also contact info fresh for next cycle)

			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let trib = scene.GetComponent<TriggerBody>(e);

				trib.prevOverlaps = trib.overlaps;
				trib.overlaps.Clear();

				let triggerBounds = MakeColliderBounds(tra.point, trib.triggers);
				let triggerMask = MakeCombinedMask(trib.triggers);
				let xMaxBucket = triggerBounds.Right / BucketSystem.BUCKET_SIZE;
				let yMaxBucket = triggerBounds.Bottom / BucketSystem.BUCKET_SIZE;
				CHECKENT:for (var y = triggerBounds.Top / BucketSystem.BUCKET_SIZE; y <= yMaxBucket; y++)
					for (var x = triggerBounds.Left / BucketSystem.BUCKET_SIZE; x <= xMaxBucket; x++)
					{
						let bucket = Point2(x, y);
						if (!buckSys.buckets.ContainsKey(bucket))
							continue;

						for (let eC in buckSys.buckets[bucket])
						{
							let traC = scene.GetComponent<Transform>(eC);
							let cob = scene.GetComponent<CollisionBody>(eC);

							let collBounds = CollisionSystem.MakeColliderBounds(traC.point, cob.colliders, triggerMask);
							if (!triggerBounds.Overlaps(collBounds))
								continue;

							for (let trig in trib.triggers)
							{
								let tRect = Rect(tra.point + trig.rect.Position, trig.rect.Size);
		
								for (let coll in cob.colliders)
									if (trig.layer.Overlaps(coll.layer))
									{
										let cRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);
		
										if (tRect.Overlaps(cRect))
										{
											trib.overlaps.Add(TriggerCollisionInfo()
												{
													other = eC,
													myColliderIndex = @trig.Index,
													otherColliderIndex = @coll.Index
												});
		
											if (scene.GetComponentOptional<TriggerOverlapFeedback>(eC, let feedback))
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

						if (scene.GetComponentOptional<TriggerOverlapFeedback>(currOver.other, let feedback))
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

		public static LayerMask MakeCombinedMask(SizedList<TriggerRect, 4> triggers)
		{
			LayerMask m = default;
			for (let trig in triggers)
				m = m.Combine(trig.layer);
			return m;
		}

		[Optimize]
		public static Rect MakeColliderBounds(Point2 pos, SizedList<TriggerRect, 4> triggers, LayerMask mask = .ALL)
		{
			var origin = pos;
			var size = Point2.Zero;

			// Get bounds
			for (let trig in triggers)
			{
				if (!trig.layer.Overlaps(mask))
					continue;

				let boxOrig = pos + trig.rect.Position;

				// Leftmost corner
				if (boxOrig.X < origin.X)
					origin.X = boxOrig.X;
				if (boxOrig.Y < origin.Y)
					origin.Y = boxOrig.Y;

				// Size
				let boxSize = trig.rect.Size;
				if (boxOrig.X + boxSize.X > origin.X + size.X)
					size.X = boxSize.X;
				if (boxOrig.Y + boxSize.Y > origin.Y + size.Y)
					size.Y = boxSize.Y;
			}

			return .(origin, size);
		}
	}
}
