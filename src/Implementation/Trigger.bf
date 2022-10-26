using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	typealias TriggerList = SizedList<TriggerEntry, const 4>;

	[BonTarget,BonPolyRegister]
	struct TriggerBody
	{
		public TriggerList triggerEntries;

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
		public Mask obstructLayer = .None;

		// Entries are all sorted by distance to the entity position

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
		public this(Rect rect, Mask tag)
		{
			this.shape = .Rect(rect);
			this.tag = tag; // By default on layer 0
		}

		public this(TriggerShape shape, Mask tag)
		{
			this.shape = shape;
			this.tag = tag; // By default on layer 0
		}

		public TriggerShape shape;
		public Mask tag;
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

					for (let overlap in entry.overlaps)
						batch.HollowCircle(scene.GetComponent<Transform>(overlap.other).point, 4, 1, 4, .Cyan);
				}
			}
		}

		[PerfTrack]
		public void TickPostColl(BucketSystem buckSys, GridSystem gridSys)
		{
			// We assume to be called after movement has taken place, otherwise updating triggers wouldn't make sense
			// i.e.: (various updates adding force, setting movement) -> collision tick & other movement finalizing things
			//		 -> trigger tick -> ... (movement & now also contact info fresh for next cycle)

			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let trib = scene.GetComponent<TriggerBody>(e);

				for (var entry in ref trib.triggerEntries)
				{
					entry.prevOverlaps = entry.overlaps;
					entry.overlaps.Clear();
				}

				let triggerBounds = MakeColliderBounds(tra.point, trib.triggerEntries);
				let triggerMask = MakeCombinedTagMask(trib.triggerEntries);
				let maxBucket = BucketSystem.WorldToBucket(triggerBounds.BottomRight);
				let minBucket = BucketSystem.WorldToBucket(triggerBounds.TopLeft);
				CHECKENT:for (var y = minBucket.Y; y <= maxBucket.Y; y++)
					for (var x = minBucket.X; x <= maxBucket.X; x++)
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

							let collBounds = CollisionSystem.MakeColliderBounds(traC.point, cob.colliders, .None, triggerMask);
							if (!triggerBounds.Overlaps(collBounds))
								continue;

							CHECKTRIG:for (let entry in trib.triggerEntries)
							{
								// An entity might be in multiple buckets at once,
								// so we might process it twice, which we at least dont want to record
								for (var info in entry.overlaps)
									if (info.other == eCollision)
										continue CHECKTRIG;

								switch (entry.trigger.shape)
								{
								case .Rect(let rect):
									let triggerRect = Rect(tra.point + rect.Position, rect.Size);

									for (let coll in cob.colliders)
										if (entry.trigger.tag.Overlaps(coll.tag))
										{
											let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);

											if (!triggerRect.Overlaps(colliderRect))
												continue;

											let entDist = colliderRect.ClampPoint(tra.point).DistanceTo(tra.point);

											HandleOverlap(@entry.Index, @coll.Index, entDist);
										}

								case .Circle(let position, let radius):
									let triggerPosition = tra.point + position;

									for (let coll in cob.colliders)
										if (entry.trigger.tag.Overlaps(coll.tag))
										{
											let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);
											let distance = colliderRect.ClampPoint(triggerPosition).DistanceTo(triggerPosition);

											if (distance > radius)
												continue;

											let endDist = colliderRect.ClampPoint(tra.point).DistanceTo(tra.point);

											HandleOverlap(@entry.Index, @coll.Index, endDist);
										}
								}

								void HandleOverlap(int triggerIndex, int otherColliderIndex, float distance)
								{
									Debug.Assert((triggerIndex | otherColliderIndex) <= uint8.MaxValue);
									var trigger = ref trib.triggerEntries[triggerIndex];

									if (trigger.obstructLayer != .None)
									{
										int range;
										switch (trigger.trigger.shape)
										{
										case .Circle(let position, let radius):
											range = radius;
										case .Rect(let rect):
											range = Math.Max(rect.Width, rect.Height); // Too much, but we already know we overlap anyway...
										}

										let info = CollisionSystem.Raycast(tra.point, (traC.point + cob.colliders[otherColliderIndex].rect.Position - tra.point).ToNormalized(), range, trigger.obstructLayer, buckSys, gridSys, scene, e);

										if (info.other != .Invalid && info.distance <= distance
											&& (info.other != eCollision || info.other == eCollision && info.otherColliderIndex != otherColliderIndex))
											return;
									}

									var insert = 0;
									for (var i = trigger.overlaps.Count - 1; i >= 0; i--)
									{
										if (trigger.overlaps[[Unchecked]i].distance <= distance)
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
									trigger.overlaps.Insert(insert, info);

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

		public static Mask MakeCombinedTagMask(TriggerList triggers)
		{
			Mask m = default;
			for (let entry in triggers)
				m = m.Combine(entry.trigger.tag);
			return m;
		}

		[Optimize]
		public static Rect MakeColliderBounds(Point2 pos, TriggerList triggers, Mask tagMask = .All)
		{
			var origin = Point2.Zero;
			var size = Point2.Zero;
			bool first = true;

			// Get bounds
			for (let entry in triggers)
			{
				if (!entry.trigger.tag.Overlaps(tagMask))
					continue;

				Rect shapeRect;
				switch (entry.trigger.shape)
				{
				case .Rect(let rect): shapeRect = rect;
				case .Circle(let position, let radius): shapeRect = .(position.X - radius, position.Y - radius, radius * 2, radius * 2);
				}

				let boxOrig = pos + shapeRect.Position;

				if (first)
				{
					origin = boxOrig;
					first = false;
				}
				else
				{
					// TopLeft corner shift
					if (boxOrig.X < origin.X)
					{
						size.X += origin.X - boxOrig.X;
						origin.X = boxOrig.X;
					}
					if (boxOrig.Y < origin.Y)
					{
						size.Y += origin.Y - boxOrig.Y;
						origin.Y = boxOrig.Y;
					}
				}

				// BottomRight corner shift
				let boxRight = boxOrig.X + shapeRect.Width;
				if (boxRight > origin.X + size.X)
					size.X = boxRight - origin.X;

				let boxBottom = boxOrig.Y + shapeRect.Height;
				if (boxBottom > origin.Y + size.Y)
					size.Y = boxBottom - origin.Y;
			}

			return .(origin, size);
		}
	}
}
