using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	[BonTarget,BonPolyRegister]
	struct TriggerBody
	{
		public SizedList<TriggerEntry, const 4> triggerEntries;

		public this(params Trigger[] colls)
		{
			this = default;

			for (let i < colls.Count)
				triggerEntries.Add(TriggerEntry() {trigger = colls[i]});
		}
	}

	[BonTarget]
	struct TriggerEntry
	{
		public Trigger trigger;

		// Entries are all sorted by distance to trigger position/"origin"

		public SizedList<TriggerOverlapInfo, const 32> overlaps;
		public SizedList<TriggerOverlapInfo, const 32> prevOverlaps;

		public SizedList<TriggerOverlapInfo, const 32> newOverlaps;
	}

	[BonTarget]
	struct TriggerOverlapInfo
	{
		public Entity other;
		public uint8 otherColliderIndex;
		public float distance;
	}

	[BonTarget]
	enum TriggerShape
	{
		case Rect(Rect rect);
		case Circle(Point2 position, int radius);
	}

	[BonTarget]
	struct Trigger
	{
		public this(Rect rect, LayerMask layer = 0x1)
		{
			this.shape = .Rect(rect);
			this.layer = layer; // By default on layer 0
		}

		public this(TriggerShape shape, LayerMask layer = 0x1)
		{
			this.shape = shape;
			this.layer = layer; // By default on layer 0
		}

		public TriggerShape shape;
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
		public uint8 myColliderIndex, otherColliderIndex;
		public float distance;
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

				for (let entry in trib.triggerEntries)
				{
					switch (entry.trigger.shape)
					{
					case .Rect(let rect): batch.HollowRect(.(tra.point + rect.Position, rect.Size), 1, .Blue);
					case .Circle(let position, let radius): batch.HollowCircle(tra.point + position, radius, 1, 24, .Blue);
					}
				}	
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

				for (var record in ref trib.triggerEntries)
				{
					record.prevOverlaps = record.overlaps;
					record.overlaps.Clear();
				}

				let triggerBounds = MakeColliderBounds(tra.point, trib.triggerEntries);
				let triggerMask = MakeCombinedMask(trib.triggerEntries);
				let xMaxBucket = triggerBounds.Right / BucketSystem.BUCKET_SIZE;
				let yMaxBucket = triggerBounds.Bottom / BucketSystem.BUCKET_SIZE;
				CHECKENT:for (var y = triggerBounds.Top / BucketSystem.BUCKET_SIZE; y <= yMaxBucket; y++)
					for (var x = triggerBounds.Left / BucketSystem.BUCKET_SIZE; x <= xMaxBucket; x++)
					{
						let bucket = Point2(x, y);
						if (!buckSys.buckets.ContainsKey(bucket))
							continue;

						for (let eCollision in buckSys.buckets[bucket])
						{
							if (eCollision == e)
								continue;

							let traC = scene.GetComponent<Transform>(eCollision);
							let cob = scene.GetComponent<CollisionBody>(eCollision);

							let collBounds = CollisionSystem.MakeColliderBounds(traC.point, cob.colliders, triggerMask);
							if (!triggerBounds.Overlaps(collBounds))
								continue;

							CHECKTRIG:for (let entry in trib.triggerEntries)
							{
								for (var info in ref trib.triggerEntries[@entry.Index].overlaps)
									if (info.other == eCollision)
										continue CHECKTRIG;

								switch (entry.trigger.shape)
								{
								case .Rect(let rect):
									let triggerRect = Rect(tra.point + rect.Position, rect.Size);

									for (let coll in cob.colliders)
										if (entry.trigger.layer.Overlaps(coll.layer))
										{
											let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);

											if (!triggerRect.Overlaps(colliderRect))
												continue;

											let distance = colliderRect.ClampPoint(triggerRect.Position).DistanceTo(triggerRect.Position);

											HandleOverlap(@entry.Index, @coll.Index, distance);
										}

								case .Circle(let position, let radius):
									let triggerPosition = tra.point + position;

									for (let coll in cob.colliders)
										if (entry.trigger.layer.Overlaps(coll.layer))
										{
											let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);
											let distance = colliderRect.ClampPoint(triggerPosition).DistanceTo(triggerPosition);

											if (distance > radius) // TODO: what about =?
												continue;

											HandleOverlap(@entry.Index, @coll.Index, distance);
										}
								}

								void HandleOverlap(int triggerIndex, int otherColliderIndex, float distance)
								{
									// TODO: check obstruction... somehow... (optional)
									// -> raycasting!

									Debug.Assert((triggerIndex | otherColliderIndex) <= uint8.MaxValue);

									var insert = 0;
									for (var i = trib.triggerEntries[triggerIndex].overlaps.Count - 1; i >= 0; i--)
									{
										if (trib.triggerEntries[triggerIndex].overlaps[[Unchecked]i].distance <= distance)
										{
											insert = i + 1;
											break;
										}
									}

									let info = TriggerOverlapInfo()
										{
											other = eCollision,
											otherColliderIndex = (.)otherColliderIndex,
											distance = distance
										};
									trib.triggerEntries[triggerIndex].overlaps.Insert(insert, info);

									if (scene.GetComponentOptional<TriggerOverlapFeedback>(eCollision, let feedback))
									{
										let collInfo = TriggerCollisionInfo()
											{
												other = e,
												otherColliderIndex = (.)triggerIndex,
												myColliderIndex = (.)otherColliderIndex,
												distance = distance
											};
										feedback.overlaps.Add(collInfo);
									}
								}
							}
						}
				}

				for (var record in ref trib.triggerEntries)
				{
					record.newOverlaps.Clear();

					for (let currOver in record.overlaps)
					{
						bool isOld = false;
						for (let prevOver in record.prevOverlaps)
						{
							if (currOver.other == prevOver.other && currOver.otherColliderIndex == prevOver.otherColliderIndex)
								isOld = true;
						}

						// This overlap is new, add it to the new list
						if (!isOld)
						{
							record.newOverlaps.Add(currOver);

							if (scene.GetComponentOptional<TriggerOverlapFeedback>(currOver.other, let feedback))
								// Technically we've already added this to the feedback.overlaps list somewhere, but we're not going to search, just make it again
								feedback.newOverlaps.Add(TriggerCollisionInfo()
									{
										other = e,
										myColliderIndex = currOver.otherColliderIndex,
										otherColliderIndex = (.)@record.Index
									});
						}
					}
				}
			}
		}

		public static LayerMask MakeCombinedMask(SizedList<TriggerEntry, 4> triggers)
		{
			LayerMask m = default;
			for (let entry in triggers)
				m = m.Combine(entry.trigger.layer);
			return m;
		}

		[Optimize]
		public static Rect MakeColliderBounds(Point2 pos, SizedList<TriggerEntry, 4> triggers, LayerMask mask = .ALL)
		{
			var origin = pos;
			var size = Point2.Zero;

			// Get bounds
			for (let entry in triggers)
			{
				if (!entry.trigger.layer.Overlaps(mask))
					continue;

				Rect shapeRect;
				switch (entry.trigger.shape)
				{
				case .Rect(let rect): shapeRect = rect;
				case .Circle(let position, let radius): shapeRect = .(position.X - radius, position.Y - radius, radius * 2, radius * 2);
				}

				let boxOrig = pos + shapeRect.Position;

				// Leftmost corner
				if (boxOrig.X < origin.X)
					origin.X = boxOrig.X;
				if (boxOrig.Y < origin.Y)
					origin.Y = boxOrig.Y;

				// Size
				let boxSize = shapeRect.Size;
				if (boxOrig.X + boxSize.X > origin.X + size.X)
					size.X = boxSize.X;
				if (boxOrig.Y + boxSize.Y > origin.Y + size.Y)
					size.Y = boxSize.Y;
			}

			return .(origin, size);
		}
	}
}
